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
    public func resolveLink(_ rawHref: String, fromKB kbID: String,
                            fromPage page: KBPage) -> (href: String, broken: Bool) {
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

    /// Render one composed page to an HTML fragment.
    public func renderHTML(_ composed: ComposedPage) -> String {
        Markdown.render(composed.page.body) { raw in
            self.resolveLink(raw, fromKB: composed.kbID, fromPage: composed.page)
        }
    }

    // MARK: - Search

    public struct SearchHit {
        public var route: String
        public var kbID: String
        public var title: String
        public var summary: String?
        public var score: Int
    }

    /// Naive full-text search across the whole composition — the
    /// corpora are small enough that an index-free scan is honest.
    public func search(_ query: String) -> [SearchHit] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        var hits: [SearchHit] = []
        for composed in pages {
            var score = 0
            if composed.page.title.lowercased().contains(q) { score += 10 }
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
            if score > 0 {
                hits.append(SearchHit(route: composed.route, kbID: composed.kbID,
                                      title: composed.page.title,
                                      summary: composed.page.summary, score: score))
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

    public func resolveLink(_ rawHref: String,
                            fromPage page: KBPage) -> (href: String, broken: Bool) {
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

    public func renderHTML(_ page: KBPage) -> String {
        Markdown.render(page.body) { raw in
            self.resolveLink(raw, fromPage: page)
        }
    }
}
