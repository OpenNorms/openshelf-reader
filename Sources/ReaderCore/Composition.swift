import Foundation

/// One page as it appears inside a composition: the page itself, the KB
/// it came from (provenance), and its composed route.
public struct ComposedPage {
    public var kbID: String
    public var page: KBPage
    /// Composed route, matching the web composition builder's scheme:
    /// `kb/<kb-id>/<slug>`.
    public var route: String

    public var title: String { page.title }
}

/// A set of knowledge bases composed into one readable whole — the
/// reader-side counterpart of the registry composition the web builder
/// produces from `.openshelf/kbs.yaml` + `kbs.lock`. Members keep their
/// identity: every page carries its source KB (and, when known, the
/// commit it was pinned at) as provenance.
public struct ComposedKB {
    public var name: String
    public var members: [KnowledgeBase]
    public var pages: [ComposedPage]

    public init(name: String, members: [KnowledgeBase]) {
        self.name = name
        self.members = members
        var composed: [ComposedPage] = []
        for kb in members {
            for page in kb.pages {
                composed.append(ComposedPage(
                    kbID: kb.id, page: page,
                    route: "kb/\(kb.id)/\(page.slug)"))
            }
        }
        self.pages = composed
    }

    public func member(id: String) -> KnowledgeBase? {
        members.first(where: { $0.id == id })
    }

    public func page(route: String) -> ComposedPage? {
        pages.first(where: { $0.route == route })
    }

    /// The member KB's pin (HEAD sha of its local copy), when known.
    public func pin(for kbID: String) -> String? {
        member(id: kbID)?.headSHA
    }

    // MARK: - Link resolution

    /// Resolve a raw markdown href found in `page` of KB `kbID` to a
    /// composed route. External URLs pass through; unresolvable
    /// internal references come back flagged broken.
    public func resolveLink(_ rawHref: String, kind: Markdown.LinkKind = .markdown,
                            fromKB kbID: String,
                            fromPage page: KBPage) -> (href: String, broken: Bool) {
        if kind == .wiki {
            let target = WikiTarget(rawHref, depends: member(id: kbID)?.manifest.depends ?? [])
            guard let (targetKB, found) = wikiPage(target, fromKB: kbID) else {
                return (rawHref, true)
            }
            return ("kb/\(targetKB)/\(found.slug)" + target.fragmentSuffix, false)
        }
        let href = rawHref.trimmingCharacters(in: .whitespaces)
        if href.isEmpty || href.hasPrefix("#") { return (href, false) }
        if href.hasPrefix("http://") || href.hasPrefix("https://")
            || href.hasPrefix("mailto:") {
            return (href, false)
        }
        if href.hasPrefix("kb://") {
            let rest = String(href.dropFirst("kb://".count))
            let parts = rest.split(separator: "/", maxSplits: 1)
            guard parts.count == 2 else { return (href, true) }
            let targetKB = String(parts[0])
            let slug = ComposedKB.stripMarkdownSuffix(String(parts[1]))
            guard let kb = member(id: targetKB), kb.page(slug: slug) != nil else {
                return (href, true)
            }
            return ("kb/\(targetKB)/\(slug)", false)
        }
        if ComposedKB.isMarkdownReference(href) {
            let slug = resolveRelative(href, fromPage: page)
            guard let kb = member(id: kbID), kb.page(slug: slug) != nil else {
                return (href, true)
            }
            return ("kb/\(kbID)/\(slug)", false)
        }
        // Anything else (images, attachments) is handed to the app,
        // which maps it into the member KB's cache directory.
        return ("kbfile://\(kbID)/\(href)", false)
    }

    private func wikiPage(_ target: WikiTarget, fromKB kbID: String) -> (String, KBPage)? {
        let targetKB = target.kb ?? kbID
        guard let kb = member(id: targetKB),
              let found = kb.resolveWikiTarget(target.pageID) else { return nil }
        return (targetKB, found)
    }

    /// Render one composed page to an HTML fragment.
    public func renderHTML(_ composed: ComposedPage, dropLeadingTitle: Bool = false) -> String {
        let depends = member(id: composed.kbID)?.manifest.depends ?? []
        return Markdown.render(dropLeadingTitle ? composed.page.bodyWithoutLeadingTitle : composed.page.body, resolveLink: { raw, kind in
            self.resolveLink(raw, kind: kind, fromKB: composed.kbID, fromPage: composed.page)
        }, wikiTitle: { raw in
            self.wikiPage(WikiTarget(raw, depends: depends), fromKB: composed.kbID)?.1.title
        })
    }

    // MARK: - Search

    public struct SearchHit {
        public var route: String
        public var kbID: String
        public var title: String
        public var summary: String?
        /// The page's `category`, else its `type` — the provenance label.
        public var category: String?
        public var score: Int
    }

    /// Naive full-text search across the composition — the corpora are
    /// small enough that an index-free scan is honest. `titlesOnly`
    /// matches titles and nothing else; `kbIDs` limits the search to
    /// those member KBs (nil = all).
    public func search(_ query: String, titlesOnly: Bool = false,
                       kbIDs: Set<String>? = nil) -> [SearchHit] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        var hits: [SearchHit] = []
        for composed in pages {
            if let kbIDs, !kbIDs.contains(composed.kbID) { continue }
            var score = 0
            if composed.page.title.lowercased().contains(q) { score += 10 }
            if !titlesOnly {
                if let s = composed.page.summary, s.lowercased().contains(q) { score += 5 }
                let body = composed.page.body.lowercased()
                var idx = body.startIndex
                var count = 0
                while let range = body.range(of: q, range: idx..<body.endIndex) {
                    count += 1
                    idx = range.upperBound
                    if count >= 5 { break }
                }
                score += count
            }
            if score > 0 {
                hits.append(SearchHit(route: composed.route, kbID: composed.kbID,
                                      title: composed.page.title,
                                      summary: composed.page.summary,
                                      category: composed.page.category ?? composed.page.type,
                                      score: score))
            }
        }
        return hits.sorted { $0.score != $1.score ? $0.score > $1.score : $0.title < $1.title }
    }

    // MARK: - Bundle (the web builder's bundle.json shape)

    public struct Bundle: Codable {
        public struct KBEntry: Codable {
            public var id: String
            public var title: String
            public var description: String
            public var commit: String?
            public var visibility: String?
        }
        public struct PageEntry: Codable {
            public var route: String
            public var kb: String
            public var slug: String
            public var title: String
            public var summary: String?
            public var type: String?
            public var updated: String?
        }
        public var name: String
        public var kbs: [KBEntry]
        public var pages: [PageEntry]
    }

    public var bundle: Bundle {
        Bundle(
            name: name,
            kbs: members.map {
                Bundle.KBEntry(id: $0.id, title: $0.title,
                               description: $0.manifest.description,
                               commit: $0.headSHA,
                               visibility: $0.manifest.visibility)
            },
            pages: pages.map {
                Bundle.PageEntry(route: $0.route, kb: $0.kbID, slug: $0.page.slug,
                                 title: $0.page.title, summary: $0.page.summary,
                                 type: $0.page.type, updated: $0.page.updated)
            })
    }

    // MARK: - Relative reference resolution

    static func isMarkdownReference(_ href: String) -> Bool {
        let path = href.split(separator: "#").first.map(String.init) ?? href
        return path.hasSuffix(".md")
    }

    static func stripMarkdownSuffix(_ slug: String) -> String {
        let path = slug.split(separator: "#").first.map(String.init) ?? slug
        return path.hasSuffix(".md") ? String(path.dropLast(3)) : path
    }

    /// Resolve a relative `.md` reference against the directory of the
    /// page that contains it, producing a slug in the same KB.
    func resolveRelative(_ href: String, fromPage page: KBPage) -> String {
        let path = href.split(separator: "#").first.map(String.init) ?? href
        var base = page.slug.split(separator: "/").map(String.init)
        if !base.isEmpty { base.removeLast() }  // the page's directory
        for component in path.split(separator: "/") {
            if component == "." { continue }
            if component == ".." {
                if !base.isEmpty { base.removeLast() }
            } else {
                base.append(String(component))
            }
        }
        return ComposedKB.stripMarkdownSuffix(base.joined(separator: "/"))
    }
}

/// Rendering a single KB on its own — the "notebook" case. Routes are
/// `page/<slug>`; resolution is the single-KB special case of the
/// composition rules.
public struct Notebook {
    public var kb: KnowledgeBase

    public init(kb: KnowledgeBase) { self.kb = kb }

    public func resolveLink(_ rawHref: String, kind: Markdown.LinkKind = .markdown,
                            fromPage page: KBPage) -> (href: String, broken: Bool) {
        if kind == .wiki {
            let target = WikiTarget(rawHref, depends: kb.manifest.depends)
            guard let found = wikiPage(target) else { return (rawHref, true) }
            return ("page/\(found.slug)" + target.fragmentSuffix, false)
        }
        let href = rawHref.trimmingCharacters(in: .whitespaces)
        if href.isEmpty || href.hasPrefix("#") { return (href, false) }
        if href.hasPrefix("http://") || href.hasPrefix("https://")
            || href.hasPrefix("mailto:") {
            return (href, false)
        }
        if ComposedKB.isMarkdownReference(href) {
            let composed = ComposedKB(name: kb.id, members: [kb])
            let slug = composed.resolveRelative(href, fromPage: page)
            guard kb.page(slug: slug) != nil else { return (href, true) }
            return ("page/\(slug)", false)
        }
        if href.hasPrefix("kb://") { return (href, true) }  // no composition here
        return ("kbfile://\(kb.id)/\(href)", false)
    }

    /// Cross-KB targets need a composition, as with kb:// links.
    private func wikiPage(_ target: WikiTarget) -> KBPage? {
        guard target.kb == nil || target.kb == kb.id else { return nil }
        return kb.resolveWikiTarget(target.pageID)
    }

    public func renderHTML(_ page: KBPage, dropLeadingTitle: Bool = false) -> String {
        Markdown.render(dropLeadingTitle ? page.bodyWithoutLeadingTitle : page.body, resolveLink: { raw, kind in
            self.resolveLink(raw, kind: kind, fromPage: page)
        }, wikiTitle: { raw in
            self.wikiPage(WikiTarget(raw, depends: self.kb.manifest.depends))?.title
        })
    }
}

/// A parsed wikilink target (spec §4.4): `page-id`, `kb://kb/page-id`,
/// or the `kb:page-id` shorthand (only for KBs listed in `depends`),
/// each optionally followed by `#heading-slug`.
struct WikiTarget {
    var kb: String?
    var pageID: String
    var fragment: String?

    var fragmentSuffix: String { fragment.map { "#\($0)" } ?? "" }

    init(_ raw: String, depends: [String]) {
        var target = raw.trimmingCharacters(in: .whitespaces)
        if let hash = target.firstIndex(of: "#") {
            let frag = String(target[target.index(after: hash)...])
            fragment = frag.isEmpty ? nil : frag
            target = String(target[..<hash])
        }
        if target.hasPrefix("kb://") {
            let parts = target.dropFirst("kb://".count).split(separator: "/", maxSplits: 1)
            kb = parts.first.map(String.init)
            target = parts.count == 2 ? String(parts[1]) : ""
        } else if let colon = target.firstIndex(of: ":"),
                  depends.contains(String(target[..<colon])) {
            kb = String(target[..<colon])
            target = String(target[target.index(after: colon)...])
        }
        while target.hasPrefix("/") { target.removeFirst() }
        pageID = ComposedKB.stripMarkdownSuffix(target)
    }
}

/// Splitting text around a search query, for drawing matches highlighted.
public enum SearchHighlight {
    public struct Segment: Equatable {
        public var text: String
        public var matched: Bool
    }

    /// `text` cut into alternating plain / matched runs for `query`
    /// (case- and diacritic-insensitive). No match, or an empty query,
    /// gives the whole text as one unmatched run.
    public static func segments(_ text: String, query: String) -> [Segment] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty, !text.isEmpty else {
            return text.isEmpty ? [] : [Segment(text: text, matched: false)]
        }
        var out: [Segment] = []
        var cursor = text.startIndex
        let opts: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        while cursor < text.endIndex,
              let r = text.range(of: q, options: opts, range: cursor..<text.endIndex) {
            if r.lowerBound > cursor {
                out.append(Segment(text: String(text[cursor..<r.lowerBound]), matched: false))
            }
            out.append(Segment(text: String(text[r]), matched: true))
            cursor = r.upperBound
        }
        if cursor < text.endIndex {
            out.append(Segment(text: String(text[cursor...]), matched: false))
        }
        return out
    }
}

/// Deterministic cover colours: the same KB id always picks the same
/// slot (a stable FNV-1a hash — Swift's own hashing is seeded per run).
public func coverPaletteIndex(for id: String, paletteSize: Int) -> Int {
    guard paletteSize > 0 else { return 0 }
    var hash: UInt64 = 0xcbf29ce484222325
    for byte in id.utf8 {
        hash ^= UInt64(byte)
        hash = hash &* 0x100000001b3
    }
    return Int(hash % UInt64(paletteSize))
}
