import Foundation
import SwiftUI
import ReaderCore

/// Navigation routes for the app's single NavigationStack.
enum Route: Hashable {
    case notebook(String)                 // cacheName
    case page(String, String)             // cacheName, slug
    case composition(String)              // composition name
    case composedPage(String, String)     // composition name, route
    case group(String, String)            // cacheName, BrowseGroup.id
    case search(String?)                  // optional cacheName to scope to
    case list(String, String)             // cacheName, PageListView.Kind raw value
}

/// Why a notebook's last pull failed, for the alert card on the library.
struct SyncFailure: Equatable, Identifiable {
    enum Kind { case auth, other }
    var cacheName: String
    var kind: Kind
    var headline: String
    var detail: String
    /// Card dismissed; the cover keeps its badge until the next good pull.
    var dismissed = false
    var id: String { cacheName }

    static func from(_ error: Error, hadToken: Bool, cacheName: String) -> SyncFailure {
        let raw = (error as? LibGit2Error)?.message ?? error.localizedDescription
        let lower = raw.lowercased()
        let code = (error as? LibGit2Error)?.code
        if code == -16 || lower.contains("authentication") || lower.contains("401")
            || lower.contains("403") || lower.contains("token") {
            return SyncFailure(
                cacheName: cacheName, kind: .auth,
                headline: hadToken ? "The access token was rejected"
                                   : "This repository needs an access token",
                detail: raw)
        }
        return SyncFailure(cacheName: cacheName, kind: .other,
                           headline: raw.prefix(1).uppercased() + raw.dropFirst(),
                           detail: raw)
    }
}

/// Live state of the Add sheet: which step is running and what it found.
struct AddProgress: Equatable {
    enum Phase: Int { case cloning, readingManifest, indexing, done }
    var phase: Phase = .cloning
    var cloneFraction: Double = 0
    var specVersion: String?
    var pageCount: Int?
    var error: String?

    /// Overall bar value: clone is 70%, then one step each.
    var fraction: Double {
        switch phase {
        case .cloning: return 0.7 * cloneFraction
        case .readingManifest: return 0.8
        case .indexing: return 0.92
        case .done: return 1
        }
    }
    var isRunning: Bool { error == nil && phase != .done }
}

/// The app's state: the persisted library, the KBs loaded from the
/// local cache, and sync bookkeeping. All git work goes through the
/// injected GitSyncEngine (libgit2 in the app); the store owns the
/// cache layout:
///
///   Application Support/OpenShelfReader/
///     library.json
///     KBs/<cacheName>/   (one git checkout per KB)
@MainActor
final class KBStore: ObservableObject {
    @Published var library = ReaderLibrary()
    @Published var loaded: [String: KnowledgeBase] = [:]
    @Published var syncing: Set<String> = []
    /// Transfer progress (0...1) of a running pull, by cacheName.
    @Published var syncProgress: [String: Double] = [:]
    /// Failed pulls by cacheName; cleared by a later success or Dismiss.
    @Published var failures: [String: SyncFailure] = [:]
    /// Non-nil while the Add sheet has work (or a failure) to show.
    @Published var addProgress: AddProgress?

    private let engine: GitSyncEngine
    private let root: URL
    private var tokens: [String: String] = [:]  // cacheName -> token (Keychain)

    init(engine: GitSyncEngine) {
        self.engine = engine
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.root = appSupport.appendingPathComponent("OpenShelfReader")
        try? FileManager.default.createDirectory(
            at: root.appendingPathComponent("KBs"),
            withIntermediateDirectories: true)
        loadLibrary()
        for entry in library.kbs {
            tokens[entry.cacheName] = Keychain.get("token-\(entry.cacheName)")
            reload(entry)
        }
    }

    // MARK: - Paths & persistence

    func cacheDir(_ cacheName: String) -> URL {
        root.appendingPathComponent("KBs").appendingPathComponent(cacheName)
    }

    private var libraryURL: URL { root.appendingPathComponent("library.json") }

    private func loadLibrary() {
        if let data = try? Data(contentsOf: libraryURL),
           let decoded = try? JSONDecoder().decode(ReaderLibrary.self, from: data) {
            library = decoded
        }
    }

    private func saveLibrary() {
        if let data = try? JSONEncoder().encode(library) {
            try? data.write(to: libraryURL, options: [.atomic])
        }
    }

    // MARK: - Appearance

    /// For `.preferredColorScheme`: nil follows the system.
    var preferredScheme: ColorScheme? {
        switch library.appearanceMode {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    /// The reading theme for the given colour mode, honouring a notebook's
    /// own override when it has one.
    func theme(for cacheName: String?, dark: Bool) -> ReaderTheme {
        if let cacheName,
           let entry = library.kbs.first(where: { $0.cacheName == cacheName }),
           let name = entry.themeName,
           let theme = ReaderTheme.bundled.first(where: { $0.name == name }) {
            return theme
        }
        return library.readingTheme(dark: dark)
    }

    func setReadingTheme(_ name: String, dark: Bool) {
        library.setReadingTheme(name, dark: dark)
        saveLibrary()
    }

    func setTheme(_ name: String?, for cacheName: String) {
        guard let idx = library.kbs.firstIndex(where: { $0.cacheName == cacheName })
        else { return }
        library.kbs[idx].themeName = name
        saveLibrary()
    }

    func setMode(_ mode: AppearanceMode) { library.appearanceMode = mode; saveLibrary() }
    func setTypeface(_ face: Typeface) { library.typeface = face; saveLibrary() }
    func setTextSize(_ size: Int) {
        library.textSize = min(max(size, ReaderTheme.minTextSize), ReaderTheme.maxTextSize)
        saveLibrary()
    }

    // MARK: - Last read

    func setLastPage(_ page: LibraryLastPage) {
        guard library.lastPage != page else { return }
        library.lastPage = page
        saveLibrary()
    }

    func noteOpened(cacheName: String, slug: String) {
        guard let idx = library.kbs.firstIndex(where: { $0.cacheName == cacheName }),
              library.kbs[idx].recentSlugs?.first != slug else { return }
        library.kbs[idx].noteOpened(slug)
        saveLibrary()
    }

    /// The Continue reading target, or nil when nothing was opened yet or
    /// the page no longer exists (removed notebook, page gone after a pull).
    var continueReading: (route: Route, title: String, subtitle: String, coverKey: String)? {
        guard let last = library.lastPage else { return nil }
        switch last.kind {
        case .notebook:
            guard let kb = loaded[last.owner], let page = kb.page(slug: last.key) else { return nil }
            return (.page(last.owner, last.key), page.title, kb.title, kb.id)
        case .composed:
            guard let comp = library.compositions.first(where: { $0.name == last.owner }),
                  let composed = composedKB(comp),
                  let target = composed.page(route: last.key) else { return nil }
            return (.composedPage(last.owner, last.key), target.title, comp.name, target.kbID)
        }
    }

    /// Cover colour key: the KB id once loaded, else its cache name.
    func coverKey(forCacheName cacheName: String) -> String {
        loaded[cacheName]?.id ?? cacheName
    }

    func cacheName(forKBID id: String) -> String? {
        loaded.first(where: { $0.value.id == id })?.key
    }

    // MARK: - KB lifecycle

    private func reload(_ entry: LibraryKB) {
        if let kb = try? KnowledgeBase.load(directory: cacheDir(entry.cacheName),
                                            headSHA: entry.headSHA) {
            loaded[entry.cacheName] = kb
        }
    }

    /// Add a KB by git remote URL: clone into the cache, read its
    /// manifest, index its pages. Progress is published in `addProgress`
    /// for the Add sheet; nothing is added to the library unless every
    /// step succeeds, so a failed attempt leaves no half-added entry and
    /// can simply be retried. Returns true on success.
    @discardableResult
    func addKB(remoteURL: String, branch: String?, token: String?) async -> Bool {
        let trimmed = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil else {
            addProgress = AddProgress(error: "That does not look like a Git URL. Use an https:// address.")
            return false
        }
        let cacheName = ReaderLibrary.cacheName(forRemote: trimmed)
        guard !library.kbs.contains(where: { $0.cacheName == cacheName }) else {
            addProgress = AddProgress(error: "That repository is already in the library.")
            return false
        }
        let token = (token?.isEmpty == false) ? token : nil
        let dir = cacheDir(cacheName)
        // A leftover from an interrupted attempt must not block a fresh clone.
        try? FileManager.default.removeItem(at: dir)
        addProgress = AddProgress()
        let engine = self.engine

        func fail(_ message: String) -> Bool {
            try? FileManager.default.removeItem(at: dir)
            addProgress?.error = message
            return false
        }

        let report: @Sendable (Double) -> Void = { [weak self] fraction in
            Task { @MainActor in self?.addProgress?.cloneFraction = fraction }
        }
        let sha: String
        do {
            sha = try await Task.detached(priority: .userInitiated) {
                try engine.cloneRepository(url: url, branch: branch, to: dir, token: token,
                                           progress: report)
            }.value
        } catch {
            return fail(SyncFailure.from(error, hadToken: token != nil, cacheName: cacheName).headline)
        }

        addProgress?.phase = .readingManifest
        let manifest: KBManifest
        do {
            manifest = try await Task.detached { try KnowledgeBase.readManifest(directory: dir) }.value
        } catch {
            return fail("This repository has no kb.yaml, so it is not an OpenShelf knowledge base.")
        }
        addProgress?.specVersion = manifest.specVersion ?? "unknown"

        addProgress?.phase = .indexing
        let kb: KnowledgeBase
        do {
            kb = try await Task.detached { try KnowledgeBase.load(directory: dir, headSHA: sha) }.value
        } catch {
            return fail("The kb.yaml in this repository could not be read.")
        }
        addProgress?.pageCount = kb.pages.count

        var entry = LibraryKB(remoteURL: trimmed, branch: branch, cacheName: cacheName)
        entry.headSHA = sha
        entry.lastPulled = Date().timeIntervalSince1970
        library.kbs.append(entry)
        saveLibrary()
        if let token {
            tokens[cacheName] = token
            Keychain.set(token, for: "token-\(cacheName)")
        }
        loaded[cacheName] = kb
        addProgress?.phase = .done
        return true
    }

    /// The Add sheet went away: forget its progress.
    func resetAdd() { addProgress = nil }

    func removeKB(_ cacheName: String) {
        library.kbs.removeAll(where: { $0.cacheName == cacheName })
        library.compositions = library.compositions.map { comp in
            var comp = comp
            comp.memberCacheNames.removeAll(where: { $0 == cacheName })
            return comp
        }.filter { !$0.memberCacheNames.isEmpty }
        loaded[cacheName] = nil
        failures[cacheName] = nil
        if library.lastPage?.owner == cacheName { library.lastPage = nil }
        try? FileManager.default.removeItem(at: cacheDir(cacheName))
        Keychain.set(nil, for: "token-\(cacheName)")
        saveLibrary()
    }

    /// Pull one KB (clone on first sync). The engine does fetch + reset
    /// to the branch tip — the cache is read-only, so no merges exist.
    /// A failure is recorded per KB in `failures`; the cached copy stays
    /// readable.
    func pull(_ entry: LibraryKB) async {
        guard !syncing.contains(entry.cacheName) else { return }
        let name = entry.cacheName
        syncing.insert(name)
        syncProgress[name] = 0
        defer { syncing.remove(name); syncProgress[name] = nil }
        let dir = cacheDir(name)
        let exists = FileManager.default.fileExists(
            atPath: dir.appendingPathComponent(".git").path)
        let engine = self.engine
        let token = tokens[name]
        let slugsBefore = loaded[name].map { Set($0.pages.map(\.slug)) }
        let shaBefore = library.kbs.first(where: { $0.cacheName == name })?.headSHA
        do {
            let progress: @Sendable (Double) -> Void = { [weak self] fraction in
                Task { @MainActor in self?.syncProgress[name] = fraction }
            }
            let sha = try await Task.detached(priority: .userInitiated) {
                if exists {
                    return try engine.pullRepository(at: dir, token: token, progress: progress)
                } else {
                    return try engine.cloneRepository(
                        url: URL(string: entry.remoteURL)!,
                        branch: entry.branch, to: dir, token: token, progress: progress)
                }
            }.value
            failures[name] = nil
            if let idx = library.kbs.firstIndex(where: { $0.cacheName == name }) {
                library.kbs[idx].headSHA = sha
                library.kbs[idx].lastPulled = Date().timeIntervalSince1970
                reload(library.kbs[idx])
                // What this pull brought in, kept until the next pull that
                // moves HEAD.
                if let slugsBefore, sha != shaBefore, let kb = loaded[name] {
                    library.kbs[idx].addedSlugs = kb.slugsAdded(since: slugsBefore)
                }
                saveLibrary()
            }
        } catch {
            failures[name] = SyncFailure.from(error, hadToken: token != nil, cacheName: name)
        }
    }

    func pullAll() async {
        for entry in library.kbs { await pull(entry) }
    }

    func dismissFailure(_ cacheName: String) { failures[cacheName]?.dismissed = true }

    /// Store a new access token for a KB (Keychain, as when it was added)
    /// and retry its pull.
    func updateToken(_ token: String, for cacheName: String) async {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        tokens[cacheName] = trimmed.isEmpty ? nil : trimmed
        Keychain.set(trimmed, for: "token-\(cacheName)")
        if let entry = library.kbs.first(where: { $0.cacheName == cacheName }) {
            await pull(entry)
        }
    }

    // MARK: - Compositions

    func addComposition(name: String, memberCacheNames: [String]) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, memberCacheNames.count >= 2 else { return }
        library.compositions.append(
            LibraryComposition(name: trimmed, memberCacheNames: memberCacheNames))
        saveLibrary()
    }

    func removeComposition(_ name: String) {
        library.compositions.removeAll(where: { $0.name == name })
        saveLibrary()
    }

    func composedKB(_ composition: LibraryComposition) -> ComposedKB? {
        let members = composition.memberCacheNames.compactMap { loaded[$0] }
        guard members.count >= 2 else { return nil }
        return ComposedKB(name: composition.name, members: members)
    }
}

/// Minimal Keychain wrapper for per-KB access tokens.
enum Keychain {
    static func set(_ value: String?, for key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "OpenShelfReader",
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
        guard let value, !value.isEmpty else { return }
        var attrs = query
        attrs[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(attrs as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        query[kSecAttrService as String] = "OpenShelfReader"
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
