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
    /// Directory (repo-relative) holding the pages; `layout.pages`, default "wiki".
    public var pagesDir: String
    /// Index file (repo-relative); `layout.index`, default "index.md".
    public var indexPath: String
    /// Log file (repo-relative); `layout.log`, default "log.md".
    public var logPath: String
    /// KB ids this KB declares it depends on (`depends:`).
    public var depends: [String]
    public var raw: [YAMLPair]

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

    /// Pages grouped for browsing: by `type` when present, ordered with
    /// overview/index first, otherwise alphabetical.
    public var typeGroups: [(type: String, pages: [KBPage])] {
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

    public enum LoadError: Error {
        case missingManifest(URL)
        case unreadableManifest(URL)
    }

    /// Load a KB from a local directory (a git checkout in the cache).
    public static func load(directory: URL, headSHA: String? = nil) throws -> KnowledgeBase {
        let fm = FileManager.default
        let manifestURL = directory.appendingPathComponent("kb.yaml")
        guard fm.fileExists(atPath: manifestURL.path) else {
            throw LoadError.missingManifest(directory)
        }
        guard let manifestText = try? String(contentsOf: manifestURL, encoding: .utf8) else {
            throw LoadError.unreadableManifest(manifestURL)
        }
        let fallbackID = directory.lastPathComponent
        let manifest = KBManifest(pairs: YAMLSubset.parse(manifestText),
                                  fallbackID: fallbackID)

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
