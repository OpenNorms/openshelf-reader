import Foundation

/// The git-sync contract between ReaderCore and the app.
///
/// The reader's model (owner's direction, 2026-11-11): each KB is a git
/// repository, cloned into a local cache on the device and synced with
/// a Git pull — periodically or on demand. The phone copy is a
/// read-only cache that is never edited, so a pull is a fetch plus a
/// reset to the branch tip: no merge or conflict machinery exists.
///
/// The engine itself (libgit2, via the app target) lives outside
/// ReaderCore so the core stays Foundation-only and testable anywhere.
/// An engine returns the HEAD commit the local copy sits at after the
/// operation — that sha is the page provenance the reader displays.
public protocol GitSyncEngine {
    /// Clone `url` into `directory` (which must not yet exist) and
    /// return the HEAD sha of the default branch.
    ///
    /// `progress` (0...1, transfer progress) is called from the engine's
    /// working thread, when the engine can report it.
    func cloneRepository(url: URL, branch: String?, to directory: URL,
                         token: String?,
                         progress: (@Sendable (Double) -> Void)?) throws -> String
    /// Fetch and reset the checkout at `directory` to its branch tip;
    /// return the new HEAD sha.
    func pullRepository(at directory: URL, token: String?,
                        progress: (@Sendable (Double) -> Void)?) throws -> String
}

/// One KB in the reader's library: where it comes from, where it is
/// cached, and what it is pinned at.
public struct LibraryKB: Codable, Equatable {
    public var remoteURL: String
    public var branch: String?
    /// Directory name inside the reader's cache (the KB id, sanitised).
    public var cacheName: String
    /// HEAD sha of the local copy; nil before the first successful pull.
    public var headSHA: String?
    /// When the local copy was last pulled (epoch seconds).
    public var lastPulled: Double?
    /// Theme override for this KB (theme name), nil = global theme.
    public var themeName: String?
    /// Pages opened in this notebook, most recent first (slugs).
    public var recentSlugs: [String]?
    /// Pages the last pull that moved HEAD brought in (slugs, by title).
    public var addedSlugs: [String]?

    public mutating func noteOpened(_ slug: String, limit: Int = 8) {
        var recent = recentSlugs ?? []
        recent.removeAll(where: { $0 == slug })
        recent.insert(slug, at: 0)
        recentSlugs = Array(recent.prefix(limit))
    }

    public init(remoteURL: String, branch: String? = nil, cacheName: String,
                headSHA: String? = nil, lastPulled: Double? = nil,
                themeName: String? = nil) {
        self.remoteURL = remoteURL
        self.branch = branch
        self.cacheName = cacheName
        self.headSHA = headSHA
        self.lastPulled = lastPulled
        self.themeName = themeName
    }
}

/// A user-made composition: a name and the cache names of its members.
public struct LibraryComposition: Codable, Equatable {
    public var name: String
    public var memberCacheNames: [String]

    public init(name: String, memberCacheNames: [String]) {
        self.name = name
        self.memberCacheNames = memberCacheNames
    }
}

/// The page the reader last opened, for the Continue reading card.
public struct LibraryLastPage: Codable, Equatable {
    public enum Kind: String, Codable { case notebook, composed }
    public var kind: Kind
    /// Notebook cache name, or composition name.
    public var owner: String
    /// Page slug (notebook) or composed route (`kb/<id>/<slug>`).
    public var key: String

    public init(kind: Kind, owner: String, key: String) {
        self.kind = kind
        self.owner = owner
        self.key = key
    }
}

/// The reader's persisted library (JSON in the app's storage).
///
/// Every field added after the first release decodes with a default, so
/// an older library.json still loads. The old single `globalThemeName`
/// is migrated into the per-mode reading themes.
public struct ReaderLibrary: Codable, Equatable {
    public var kbs: [LibraryKB] = []
    public var compositions: [LibraryComposition] = []
    public var appearanceMode: AppearanceMode = .system
    public var typeface: Typeface = .serif
    /// Reader text size in px, 14...24.
    public var textSize: Int = ReaderTheme.defaultTextSize
    /// Reading theme remembered for each colour mode.
    public var darkThemeName: String = ReaderTheme.ink.name
    public var lightThemeName: String = ReaderTheme.paper.name
    public var lastPage: LibraryLastPage?

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case kbs, compositions, appearanceMode, typeface, textSize
        case darkThemeName, lightThemeName, lastPage
        case globalThemeName  // legacy, read only
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kbs = try c.decodeIfPresent([LibraryKB].self, forKey: .kbs) ?? []
        compositions = try c.decodeIfPresent([LibraryComposition].self, forKey: .compositions) ?? []
        // Unknown raw values (a newer build's) fall back to the default.
        appearanceMode = (try? c.decodeIfPresent(AppearanceMode.self, forKey: .appearanceMode)) ?? .system
        typeface = (try? c.decodeIfPresent(Typeface.self, forKey: .typeface)) ?? .serif
        let size = try c.decodeIfPresent(Int.self, forKey: .textSize) ?? ReaderTheme.defaultTextSize
        textSize = min(max(size, ReaderTheme.minTextSize), ReaderTheme.maxTextSize)
        lastPage = try c.decodeIfPresent(LibraryLastPage.self, forKey: .lastPage)
        if let dark = try c.decodeIfPresent(String.self, forKey: .darkThemeName) {
            darkThemeName = dark
        }
        if let light = try c.decodeIfPresent(String.self, forKey: .lightThemeName) {
            lightThemeName = light
        }
        // Migration: the one global theme becomes the theme for the mode
        // it belongs to; the other mode keeps its default.
        if let legacy = try c.decodeIfPresent(String.self, forKey: .globalThemeName),
           !c.contains(.darkThemeName), !c.contains(.lightThemeName),
           let theme = ReaderTheme.bundled.first(where: { $0.name == legacy }) {
            if theme.isDark { darkThemeName = theme.name } else { lightThemeName = theme.name }
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kbs, forKey: .kbs)
        try c.encode(compositions, forKey: .compositions)
        try c.encode(appearanceMode, forKey: .appearanceMode)
        try c.encode(typeface, forKey: .typeface)
        try c.encode(textSize, forKey: .textSize)
        try c.encode(darkThemeName, forKey: .darkThemeName)
        try c.encode(lightThemeName, forKey: .lightThemeName)
        try c.encodeIfPresent(lastPage, forKey: .lastPage)
    }

    /// The remembered reading theme for a colour mode.
    public func readingTheme(dark: Bool) -> ReaderTheme {
        let name = dark ? darkThemeName : lightThemeName
        return ReaderTheme.bundled.first(where: { $0.name == name })
            ?? (dark ? .ink : .paper)
    }

    public mutating func setReadingTheme(_ name: String, dark: Bool) {
        if dark { darkThemeName = name } else { lightThemeName = name }
    }

    /// Derive a cache directory name from a git remote URL:
    /// "https://github.com/OpenNorms/openshelf" -> "OpenNorms-openshelf".
    public static func cacheName(forRemote url: String) -> String {
        var s = url.trimmingCharacters(in: .whitespaces)
        if s.hasSuffix(".git") { s = String(s.dropLast(4)) }
        let parts = s.split(separator: "/").map(String.init)
        let tail = parts.suffix(2).joined(separator: "-")
        let cleaned = tail.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) || scalar == "-"
                ? Character(scalar) : "-"
        }
        return String(cleaned).isEmpty ? "kb" : String(cleaned)
    }
}
