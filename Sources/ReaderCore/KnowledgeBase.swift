import Foundation

/// The parsed `kb.yaml` manifest of one OpenShelf knowledge base.
/// Parsing is tolerant (spec rule for the reader): known keys are read,
/// unknown keys — including `x-*` extension blocks — are ignored, and a
/// spec version the reader has not seen is never an error.
public struct KBManifest {
    public var id: String
    public var uid: String?
    public var title: String
    public var description: String
    public var visibility: String?
    public var profile: String?
    public var specVersion: String?
    /// The KB's own release version and licence (`version:`, `license:`),
    /// shown on its cover and notebook header.
    public var version: String?
    public var license: String?
    /// Directory (repo-relative) holding the pages; `layout.pages`, default "wiki".
    public var pagesDir: String
    /// Index file (repo-relative); `layout.index`, default "index.md".
    public var indexPath: String
    /// Log file (repo-relative); `layout.log`, default "log.md".
    public var logPath: String
    /// KB ids this KB declares it depends on (`depends:`).
    public var depends: [String]
    public var raw: [YAMLPair]

    /// The title without a trailing parenthetical, for large headers:
    /// "Embedded Security (Awesome KB)" -> "Embedded Security".
    public var shortTitle: String {
        guard title.hasSuffix(")"), let open = title.lastIndex(of: "(") else { return title }
        let head = title[..<open].trimmingCharacters(in: .whitespaces)
        return head.isEmpty ? title : head
    }

    public init(pairs: [YAMLPair], fallbackID: String) {
        let root = YAMLValue.map(pairs)
        self.raw = pairs
        self.specVersion = root.string(forKey: "openshelf")
        self.id = root.string(forKey: "id") ?? fallbackID
        self.uid = root.string(forKey: "uid")
        self.title = root.string(forKey: "title") ?? fallbackID
        self.description = root.string(forKey: "description") ?? ""
        self.visibility = root.string(forKey: "visibility")
        self.profile = root.string(forKey: "profile")
        self.version = root.string(forKey: "version")
        self.license = root.string(forKey: "license")
        let layout = root.value(forKey: "layout")
        self.pagesDir = layout?.string(forKey: "pages") ?? "wiki"
        self.indexPath = layout?.string(forKey: "index") ?? "index.md"
        self.logPath = layout?.string(forKey: "log") ?? "log.md"
        self.depends = root.stringList(forKey: "depends")
    }
}

/// One markdown page of a KB: its frontmatter, its body, and the
/// derived display fields the reader renders.
public struct KBPage {
    /// Path within the pages directory, without `.md`, e.g. "concepts/deep-dive".
    public var slug: String
    /// Repo-relative path of the file, e.g. "wiki/concepts/deep-dive.md".
    public var relativePath: String
    public var frontmatter: [String: YAMLValue]
    public var body: String

    public var title: String
    public var summary: String?
    public var type: String?
    /// Optional `category:` — what the notebook's Categories view groups by.
    public var category: String?
    /// Optional `depth:` — drawn as a second chip under the page header.
    public var depth: String?
    public var updated: String?
    /// The fleet's precedent for a rich-rendered field (target KBs).
    public var verdict: String?
    public var sources: [String]

    public init(slug: String, relativePath: String, markdown: String) {
        self.slug = slug
        self.relativePath = relativePath
        let (fm, body) = KBPage.splitFrontmatter(markdown)
        self.frontmatter = fm
        self.body = body
        self.summary = fm["summary"]?.scalarValue
        self.type = fm["type"]?.scalarValue
        self.category = fm["category"]?.scalarValue.flatMap { $0.isEmpty ? nil : $0 }
        self.depth = fm["depth"]?.scalarValue.flatMap { $0.isEmpty ? nil : $0 }
        self.updated = fm["updated"]?.scalarValue
        self.verdict = fm["verdict"]?.scalarValue
        if let src = fm["sources"] {
            switch src {
            case .list(let items):
                self.sources = items.map { item in
                    if let url = item.string(forKey: "url") { return url }
                    return item.scalarValue ?? ""
                }.filter { !$0.isEmpty }
            case .scalar(let s):
                self.sources = s.isEmpty ? [] : [s]
            case .map:
                self.sources = []
            }
        } else {
            self.sources = []
        }
        if let t = fm["title"]?.scalarValue, !t.isEmpty {
            self.title = t
        } else if let heading = KBPage.firstHeading(body) {
            self.title = heading
        } else {
            self.title = slug.split(separator: "/").last.map(String.init) ?? slug
        }
    }

    /// The body without its leading `# Title` line when that line repeats
    /// the page title (the reader shows the title in its own header).
    public var bodyWithoutLeadingTitle: String {
        var lines = body.components(separatedBy: "\n")
        guard let first = lines.firstIndex(where: {
            !$0.trimmingCharacters(in: .whitespaces).isEmpty
        }) else { return body }
        let t = lines[first].trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("# "),
              t.dropFirst(2).trimmingCharacters(in: .whitespaces)
                  .caseInsensitiveCompare(title) == .orderedSame else { return body }
        lines.remove(at: first)
        return lines.joined(separator: "\n")
    }

    /// Every frontmatter field as display pairs for the generic metadata
    /// section — nothing is silently dropped (spec fit rule).
    public var metadataPairs: [(key: String, value: String)] {
        frontmatter.keys.sorted().map { key in
            (key: key, value: KBPage.displayValue(frontmatter[key]!))
        }
    }

    public static func displayValue(_ value: YAMLValue) -> String {
        switch value {
        case .scalar(let s): return s
        case .list(let items): return items.map(displayValue).joined(separator: ", ")
        case .map(let pairs):
            return pairs.map { "\($0.key): \(displayValue($0.value))" }
                .joined(separator: "; ")
        }
    }

    public static func splitFrontmatter(_ markdown: String) -> ([String: YAMLValue], String) {
        var text = markdown
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        guard text.hasPrefix("---") else { return ([:], text) }
        let lines = text.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else {
            return ([:], text)
        }
        var end: Int? = nil
        for i in 1..<lines.count {
            let t = lines[i].trimmingCharacters(in: .whitespaces)
            if t == "---" || t == "..." { end = i; break }
        }
        guard let endIdx = end else { return ([:], text) }
        let fmText = lines[1..<endIdx].joined(separator: "\n")
        let body = lines[(endIdx + 1)...].joined(separator: "\n")
        return (YAMLSubset.parseMap(fmText), body)
    }

    public static func firstHeading(_ body: String) -> String? {
        for line in body.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("# ") {
                return String(t.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }
}

/// A loaded knowledge base: manifest + pages + where it lives on disk.
public struct KnowledgeBase {
    public var manifest: KBManifest
    public var pages: [KBPage]
    /// Local directory the KB is checked out in (the reader's cache).
    public var directory: URL
    /// Commit the local copy is pinned to, when known.
    public var headSHA: String?

    public var id: String { manifest.id }
    public var title: String { manifest.title }

    public func page(slug: String) -> KBPage? {
        pages.first(where: { $0.slug == slug })
    }

    /// Resolve a wikilink page id (spec §4.4): the page whose id matches;
    /// otherwise the only page with that file name (or trailing path).
    /// Nil when nothing matches or the name is ambiguous.
    public func resolveWikiTarget(_ id: String) -> KBPage? {
        guard !id.isEmpty else { return nil }
        if let exact = page(slug: id) { return exact }
        let matches = pages.filter { $0.slug.hasSuffix("/" + id) }
        return matches.count == 1 ? matches[0] : nil
    }

    /// Pages grouped for browsing: by `type` when present, ordered with
    /// overview/index first, otherwise alphabetical.
    public var typeGroups: [(type: String, pages: [KBPage])] {
        KnowledgeBase.groupByType(pages)
    }

    static func groupByType(_ pages: [KBPage]) -> [(type: String, pages: [KBPage])] {
        var groups: [String: [KBPage]] = [:]
        for page in pages {
            groups[page.type ?? "page", default: []].append(page)
        }
        let order = ["overview", "index", "log", "entity", "concept",
                     "source", "comparison", "synthesis", "answer", "page"]
        return groups.keys.sorted { a, b in
            let ia = order.firstIndex(of: a) ?? order.count
            let ib = order.firstIndex(of: b) ?? order.count
            return ia != ib ? ia < ib : a < b
        }.map { (type: $0, pages: groups[$0]!.sorted { $0.title < $1.title }) }
    }

    /// One row of the notebook's Categories view.
    public struct BrowseGroup: Equatable {
        public enum Kind: String { case category, type }
        public var kind: Kind
        /// The category or type value (type is lowercase as authored).
        public var key: String
        public var pages: [KBPage]

        /// Stable id for routing: `c:<category>` or `t:<type>`.
        public var id: String { (kind == .category ? "c:" : "t:") + key }
        public var title: String { kind == .category ? key : key.capitalized }
        public static func == (a: BrowseGroup, b: BrowseGroup) -> Bool {
            a.id == b.id && a.pages.map(\.slug) == b.pages.map(\.slug)
        }
    }

    /// Categories view: pages that carry a `category` are grouped by it
    /// (largest group first, then name); pages without one fall back to
    /// the `type` grouping, listed after the categories.
    public var browseGroups: [BrowseGroup] {
        var byCategory: [String: [KBPage]] = [:]
        var uncategorised: [KBPage] = []
        for page in listedPages {
            if let c = page.category { byCategory[c, default: []].append(page) }
            else { uncategorised.append(page) }
        }
        let categories = byCategory.map { key, pages in
            BrowseGroup(kind: .category, key: key,
                        pages: pages.sorted(by: KnowledgeBase.byTitle))
        }.sorted { a, b in
            a.pages.count != b.pages.count
                ? a.pages.count > b.pages.count
                : a.key.localizedCaseInsensitiveCompare(b.key) == .orderedAscending
        }
        let types = KnowledgeBase.groupByType(uncategorised).map {
            BrowseGroup(kind: .type, key: $0.type, pages: $0.pages)
        }
        return categories + types
    }

    public func browseGroup(id: String) -> BrowseGroup? {
        browseGroups.first(where: { $0.id == id })
    }

    /// A to Z: every page by title, case-insensitive.
    public var pagesAtoZ: [KBPage] { listedPages.sorted(by: KnowledgeBase.byTitle) }

    /// Recently updated: newest `updated` first (ISO dates sort as text);
    /// pages without a date come last, by title.
    public var pagesByRecency: [KBPage] {
        listedPages.sorted { a, b in
            switch (a.updated, b.updated) {
            case let (x?, y?) where x != y: return x > y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return KnowledgeBase.byTitle(a, b)
            }
        }
    }

    // MARK: Landing page

    /// A generated per-category listing (`index-<category>.md`, no
    /// frontmatter). The notebook's own Contents already shows the same
    /// thing, so these are left out of the browse lists (search and links
    /// still reach them).
    public static func isGeneratedIndex(_ page: KBPage) -> Bool {
        page.frontmatter.isEmpty
            && (page.slug.split(separator: "/").last ?? "").hasPrefix("index-")
    }

    /// The pages the browse lists show.
    public var listedPages: [KBPage] {
        pages.filter { !KnowledgeBase.isGeneratedIndex($0) }
    }

    /// The author's front page (`layout.index`).
    public var overviewPage: KBPage? {
        pages.first(where: { $0.relativePath == manifest.indexPath })
    }

    /// The change log (`layout.log`).
    public var logPage: KBPage? {
        pages.first(where: { $0.relativePath == manifest.logPath })
    }

    /// One `## [date] kind | title` heading of the log.
    public struct LogEntry: Equatable {
        public var date: String
        public var kind: String?
        public var title: String
    }

    /// The newest log entry (latest date; the later one in the file on a tie).
    public var latestLogEntry: LogEntry? {
        guard let log = logPage else { return nil }
        var best: LogEntry?
        for line in log.body.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("## ["), let close = t.firstIndex(of: "]") else { continue }
            let date = String(t[t.index(t.startIndex, offsetBy: 4)..<close])
            let rest = t[t.index(after: close)...].trimmingCharacters(in: .whitespaces)
            let parts = rest.split(separator: "|", maxSplits: 1)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            let entry = parts.count == 2
                ? LogEntry(date: date, kind: parts[0], title: parts[1])
                : LogEntry(date: date, kind: nil, title: rest)
            if let current = best, entry.date < current.date { continue }
            best = entry
        }
        return best
    }

    /// Listed pages that were not in `old` (the slugs before a pull), by title.
    public func slugsAdded(since old: Set<String>) -> [String] {
        listedPages.filter { !old.contains($0.slug) }
            .sorted(by: KnowledgeBase.byTitle).map(\.slug)
    }

    static func byTitle(_ a: KBPage, _ b: KBPage) -> Bool {
        let order = a.title.localizedCaseInsensitiveCompare(b.title)
        return order != .orderedSame ? order == .orderedAscending : a.slug < b.slug
    }

    public enum LoadError: Error {
        case missingManifest(URL)
        case unreadableManifest(URL)
    }

    /// Read just `kb.yaml` of a checkout (the cheap first step of a load).
    public static func readManifest(directory: URL) throws -> KBManifest {
        let manifestURL = directory.appendingPathComponent("kb.yaml")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw LoadError.missingManifest(directory)
        }
        guard let manifestText = try? String(contentsOf: manifestURL, encoding: .utf8) else {
            throw LoadError.unreadableManifest(manifestURL)
        }
        return KBManifest(pairs: YAMLSubset.parse(manifestText),
                          fallbackID: directory.lastPathComponent)
    }

    /// Load a KB from a local directory (a git checkout in the cache).
    public static func load(directory: URL, headSHA: String? = nil) throws -> KnowledgeBase {
        let fm = FileManager.default
        let manifest = try readManifest(directory: directory)
        var pages: [KBPage] = []
        var seen = Set<String>()
        let pagesRoot = directory.appendingPathComponent(manifest.pagesDir)
        if let enumerator = fm.enumerator(at: pagesRoot,
                                          includingPropertiesForKeys: nil,
                                          options: [.skipsHiddenFiles]) {
            for case let fileURL as URL in enumerator
            where fileURL.pathExtension == "md" {
                let rel = relativePath(of: fileURL, under: directory)
                let slug = String(rel.dropFirst(manifest.pagesDir.count + 1).dropLast(3))
                if let text = try? String(contentsOf: fileURL, encoding: .utf8) {
                    pages.append(KBPage(slug: slug, relativePath: rel, markdown: text))
                    seen.insert(rel)
                }
            }
        }
        // Index and log are first-class pages even when they live at the
        // repo root rather than under the pages directory.
        for special in [manifest.indexPath, manifest.logPath] {
            if seen.contains(special) { continue }
            let url = directory.appendingPathComponent(special)
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                let kind = special == manifest.indexPath ? "index" : "log"
                var page = KBPage(slug: kind, relativePath: special, markdown: text)
                if page.type == nil { page.type = kind }
                pages.append(page)
                seen.insert(special)
            }
        }
        pages.sort { $0.slug < $1.slug }
        return KnowledgeBase(manifest: manifest, pages: pages,
                             directory: directory, headSHA: headSHA)
    }

    private static func relativePath(of url: URL, under base: URL) -> String {
        let basePath = base.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        if path.hasPrefix(basePath + "/") {
            return String(path.dropFirst(basePath.count + 1))
        }
        return url.lastPathComponent
    }
}
