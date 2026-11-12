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
    func cloneRepository(url: URL, branch: String?, to directory: URL,
                         token: String?) throws -> String
    /// Fetch and reset the checkout at `directory` to its branch tip;
    /// return the new HEAD sha.
    func pullRepository(at directory: URL, token: String?) throws -> String
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

/// The reader's persisted library (JSON in the app's storage).
public struct ReaderLibrary: Codable, Equatable {
    public var kbs: [LibraryKB] = []
    public var compositions: [LibraryComposition] = []
    public var globalThemeName: String = "Ink"

    public init() {}

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
