import Foundation
import ReaderCore

/// Navigation routes for the app's single NavigationStack.
enum Route: Hashable {
    case notebook(String)                 // cacheName
    case page(String, String)             // cacheName, slug
    case composition(String)              // composition name
    case composedPage(String, String)     // composition name, route
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
    @Published var lastError: String?

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

    // MARK: - Themes

    var globalTheme: ReaderTheme {
        ReaderTheme.bundled.first(where: { $0.name == library.globalThemeName })
            ?? .ink
    }

    func theme(for cacheName: String) -> ReaderTheme {
        if let entry = library.kbs.first(where: { $0.cacheName == cacheName }),
           let name = entry.themeName,
           let theme = ReaderTheme.bundled.first(where: { $0.name == name }) {
            return theme
        }
        return globalTheme
    }

    func setGlobalTheme(_ name: String) {
        library.globalThemeName = name
        saveLibrary()
        objectWillChange.send()
    }

    func setTheme(_ name: String?, for cacheName: String) {
        guard let idx = library.kbs.firstIndex(where: { $0.cacheName == cacheName })
        else { return }
        library.kbs[idx].themeName = name
        saveLibrary()
        objectWillChange.send()
    }

    // MARK: - KB lifecycle

    private func reload(_ entry: LibraryKB) {
        if let kb = try? KnowledgeBase.load(directory: cacheDir(entry.cacheName),
                                            headSHA: entry.headSHA) {
            loaded[entry.cacheName] = kb
        }
    }

    /// Add a KB by git remote URL: clone into the cache, then load.
    func addKB(remoteURL: String, branch: String?, token: String?) async {
        let trimmed = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let cacheName = ReaderLibrary.cacheName(forRemote: trimmed)
        guard !library.kbs.contains(where: { $0.cacheName == cacheName }) else {
            lastError = "That repository is already in the library."
            return
        }
        let entry = LibraryKB(remoteURL: trimmed, branch: branch,
                              cacheName: cacheName)
        library.kbs.append(entry)
        saveLibrary()
        if let token, !token.isEmpty {
            tokens[cacheName] = token
            Keychain.set(token, for: "token-\(cacheName)")
        }
        await pull(entry)
    }

    func removeKB(_ cacheName: String) {
        library.kbs.removeAll(where: { $0.cacheName == cacheName })
        library.compositions = library.compositions.map { comp in
            var comp = comp
            comp.memberCacheNames.removeAll(where: { $0 == cacheName })
            return comp
        }.filter { !$0.memberCacheNames.isEmpty }
        loaded[cacheName] = nil
        try? FileManager.default.removeItem(at: cacheDir(cacheName))
        Keychain.set(nil, for: "token-\(cacheName)")
        saveLibrary()
    }

    /// Pull one KB (clone on first sync). The engine does fetch + reset
    /// to the branch tip — the cache is read-only, so no merges exist.
    func pull(_ entry: LibraryKB) async {
        guard !syncing.contains(entry.cacheName) else { return }
        syncing.insert(entry.cacheName)
        defer { syncing.remove(entry.cacheName) }
        let dir = cacheDir(entry.cacheName)
        let exists = FileManager.default.fileExists(
            atPath: dir.appendingPathComponent(".git").path)
        let engine = self.engine
        let token = tokens[entry.cacheName]
        do {
            let sha = try await Task.detached(priority: .userInitiated) {
                if exists {
                    return try engine.pullRepository(at: dir, token: token)
                } else {
                    return try engine.cloneRepository(
                        url: URL(string: entry.remoteURL)!,
                        branch: entry.branch, to: dir, token: token)
                }
            }.value
            if let idx = library.kbs.firstIndex(
                where: { $0.cacheName == entry.cacheName }) {
                library.kbs[idx].headSHA = sha
                library.kbs[idx].lastPulled = Date().timeIntervalSince1970
                saveLibrary()
                reload(library.kbs[idx])
            }
        } catch {
            lastError = "Sync failed for \(entry.cacheName): \(error.localizedDescription)"
        }
    }

    func pullAll() async {
        for entry in library.kbs { await pull(entry) }
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
