import XCTest
@testable import ReaderCore

final class ReaderCoreTests: XCTestCase {

    private func fixtureDir(_ name: String) -> URL {
        Bundle.module.url(forResource: "Fixtures", withExtension: nil)!
            .appendingPathComponent(name)
    }

    private func loadMini() throws -> KnowledgeBase {
        try KnowledgeBase.load(directory: fixtureDir("mini-kb"),
                               headSHA: "abc1234")
    }

    private func loadOther() throws -> KnowledgeBase {
        try KnowledgeBase.load(directory: fixtureDir("other-kb"))
    }

    // MARK: - Manifest parsing

    func testManifest17() throws {
        let kb = try loadMini()
        XCTAssertEqual(kb.manifest.id, "mini-kb")
        XCTAssertEqual(kb.manifest.title, "Mini KB")
        XCTAssertEqual(kb.manifest.specVersion, "1.7")
        XCTAssertEqual(kb.manifest.visibility, "private")
        // Folded scalar joins with spaces.
        XCTAssertEqual(kb.manifest.description,
                       "A small fixture knowledge base for reader tests.")
        XCTAssertEqual(kb.manifest.pagesDir, "wiki")
    }

    func testManifest14WithLayoutAndExtensionBlock() throws {
        let kb = try loadOther()
        XCTAssertEqual(kb.manifest.id, "other-kb")
        XCTAssertEqual(kb.manifest.specVersion, "1.4")
        XCTAssertEqual(kb.manifest.profile, "awesome")
        XCTAssertEqual(kb.manifest.pagesDir, "wiki")
        XCTAssertEqual(kb.manifest.depends, ["mini-kb"])
        // The x-ingest block parsed without disturbing known keys.
        XCTAssertEqual(kb.manifest.title, "Other KB")
    }

    // MARK: - Page loading

    func testLoadPagesAndFrontmatter() throws {
        let kb = try loadMini()
        let slugs = Set(kb.pages.map(\.slug))
        XCTAssertTrue(slugs.contains("overview"))
        XCTAssertTrue(slugs.contains("entity-one"))
        XCTAssertTrue(slugs.contains("plain-page"))
        XCTAssertTrue(slugs.contains("index"))
        XCTAssertTrue(slugs.contains("log"))

        let entity = try XCTUnwrap(kb.page(slug: "entity-one"))
        XCTAssertEqual(entity.title, "Entity One")
        XCTAssertEqual(entity.verdict, "assessed-candidate")
        XCTAssertEqual(entity.type, "entity")
        XCTAssertEqual(entity.sources, ["https://example.com/recon"])
        // The nested render: block with an inline score list parses.
        let render = try XCTUnwrap(entity.frontmatter["render"])
        XCTAssertEqual(render.string(forKey: "group"), "assessed")
        XCTAssertEqual(render.value(forKey: "scores")?.listValue?.count, 8)
        // Generic metadata carries every field, nothing dropped.
        XCTAssertTrue(entity.metadataPairs.contains { $0.key == "verdict" })

        // No frontmatter: title falls back to the first heading.
        let plain = try XCTUnwrap(kb.page(slug: "plain-page"))
        XCTAssertEqual(plain.title, "Plain Title From Heading")
        XCTAssertNil(plain.type)
    }

    func testNestedPageSlug() throws {
        let kb = try loadOther()
        XCTAssertNotNil(kb.page(slug: "concepts/deep-page"))
    }

    // MARK: - Markdown + notebook rendering

    func testNotebookRendering() throws {
        let kb = try loadMini()
        let notebook = Notebook(kb: kb)
        let overview = try XCTUnwrap(kb.page(slug: "overview"))
        let html = notebook.renderHTML(overview)
        XCTAssertTrue(html.contains("href=\"page/entity-one\""), html)
        XCTAssertTrue(html.contains("<table>"), html)
        XCTAssertTrue(html.contains("<code>verdict:</code>"), html)
        XCTAssertFalse(html.contains("class=\"broken\""), html)
    }

    func testMarkdownBasics() {
        let html = Markdown.render("# Title\n\nSome **bold** and *italic* and `code`.\n\n- one\n- two\n")
        XCTAssertTrue(html.contains("<h1 id=\"title\">Title</h1>"), html)
        XCTAssertTrue(html.contains("<strong>bold</strong>"), html)
        XCTAssertTrue(html.contains("<em>italic</em>"), html)
        XCTAssertTrue(html.contains("<code>code</code>"), html)
        XCTAssertTrue(html.contains("<li>one</li>"), html)
    }

    func testBareURLsAutolink() {
        let html = Markdown.render("""
        See https://example.com/docs. Also (https://x.org/a_(b)) and <https://y.org/q?a=1&b=2>.
        Already linked: [https://z.org](https://z.org) and [site](https://w.org/x_y_z).
        Code `https://not.a.link` stays.
        """)
        XCTAssertTrue(html.contains("<a href=\"https://example.com/docs\">https://example.com/docs</a>."), html)
        XCTAssertTrue(html.contains("(<a href=\"https://x.org/a_(b)\">https://x.org/a_(b)</a>)"), html)
        XCTAssertTrue(html.contains("<a href=\"https://y.org/q?a=1&amp;b=2\">https://y.org/q?a=1&amp;b=2</a>."), html)
        XCTAssertTrue(html.contains("<a href=\"https://z.org\">https://z.org</a>"), html)
        XCTAssertFalse(html.contains("<a href=\"https://z.org\"><a"), html)
        XCTAssertTrue(html.contains("<a href=\"https://w.org/x_y_z\">site</a>"), html)
        XCTAssertTrue(html.contains("<code>https://not.a.link</code>"), html)
        XCTAssertEqual(html.components(separatedBy: "<a ").count - 1, 5, html)
    }

    func testHTMLCommentsAreHidden() {
        let md = """
        Intro <!-- openshelf:budget-override reason="x" --> text.

        <!-- openshelf:budget-override
             reason: spans lines -->
        After.

        Literal `<!-- kept -->` in code.

        ```html
        <!-- kept in fence -->
        ```
        """
        let html = Markdown.render(md)
        XCTAssertFalse(html.contains("budget-override"), html)
        XCTAssertFalse(html.contains("spans lines"), html)
        XCTAssertTrue(html.contains("<p>Intro  text.</p>"), html)
        XCTAssertTrue(html.contains("<p>After.</p>"), html)
        XCTAssertTrue(html.contains("<code>&lt;!-- kept --&gt;</code>"), html)
        XCTAssertTrue(html.contains("&lt;!-- kept in fence --&gt;"), html)
    }

    // MARK: - Wikilinks (spec 4.4)

    func testNotebookWikilinks() throws {
        let kb = try loadMini()
        let page = try XCTUnwrap(kb.page(slug: "wikilinks"))
        let html = Notebook(kb: kb).renderHTML(page)
        func link(_ href: String, _ label: String, broken: Bool = false) -> String {
            "<a href=\"\(href)\"\(broken ? " class=\"broken\"" : "")>\(label)</a>"
        }
        let briefing = try XCTUnwrap(kb.page(slug: "briefings/2026/11/2026-11-06")).title
        let entity = try XCTUnwrap(kb.page(slug: "entity-one")).title
        // Unlabelled wikilinks show the target page's title, not its path.
        // Full id and file-name-only forms both land on the briefing.
        XCTAssertEqual(html.components(separatedBy: link("page/briefings/2026/11/2026-11-06",
                                                         briefing)).count - 1, 2, html)
        XCTAssertTrue(html.contains(link("page/entity-one", "the entity")), html)
        XCTAssertTrue(html.contains(link("page/entity-one#details", entity)), html)
        XCTAssertFalse(html.contains(">entity-one.md<"), html)
        XCTAssertTrue(html.contains(link("dup", "dup", broken: true)), html)
        XCTAssertTrue(html.contains(link("page/notes/a/dup", "Dup a")), html)
        // Broken: last path segment, never the full path.
        XCTAssertTrue(html.contains(link("no-such-page", "no-such-page", broken: true)), html)
        XCTAssertTrue(html.contains(link("projects/evoteam", "evoteam", broken: true)), html)
        XCTAssertTrue(html.contains("<code>[[entity-one]]</code>"), html)
        let outsideCode = html.replacingOccurrences(of: "<code>[[entity-one]]</code>", with: "")
        XCTAssertFalse(outsideCode.contains("[["), outsideCode)
    }

    func testComposedWikilinksAcrossKBs() throws {
        let composed = ComposedKB(name: "c", members: [try loadMini(), try loadOther()])
        let page = try XCTUnwrap(composed.page(route: "kb/other-kb/concepts/wiki-cross"))
        let html = composed.renderHTML(page)
        XCTAssertTrue(html.contains("<a href=\"kb/mini-kb/entity-one\">Entity</a>"), html)
        // Shorthand is valid because other-kb lists mini-kb in depends.
        XCTAssertTrue(html.contains("href=\"kb/mini-kb/briefings/2026/11/2026-11-06\""), html)
        // Undeclared prefix is a local page id with a colon: broken.
        XCTAssertTrue(html.contains("<a href=\"stranger:entity-one\" class=\"broken\">entity-one</a>"), html)
        let overview = try XCTUnwrap(composed.page(route: "kb/other-kb/overview")).page.title
        XCTAssertTrue(html.contains("<a href=\"kb/other-kb/overview\">\(overview)</a>"), html)
        XCTAssertTrue(html.contains(">Briefing 2026-11-06</a>"), html)
    }

    // MARK: - Composition

    func testCompositionRoutesAndCrossKBLinks() throws {
        let mini = try loadMini()
        let other = try loadOther()
        let composed = ComposedKB(name: "Test composition", members: [mini, other])

        XCTAssertNotNil(composed.page(route: "kb/mini-kb/entity-one"))
        XCTAssertEqual(composed.pin(for: "mini-kb"), "abc1234")

        let deep = try XCTUnwrap(composed.page(route: "kb/other-kb/concepts/deep-page"))
        let html = composed.renderHTML(deep)
        // kb:// link resolves into the composed route.
        XCTAssertTrue(html.contains("href=\"kb/mini-kb/entity-one\""), html)
        // Relative link resolves within the same KB.
        XCTAssertTrue(html.contains("href=\"kb/other-kb/overview\""), html)
        // The missing page is flagged broken.
        XCTAssertTrue(html.contains("class=\"broken\""), html)

        // Bundle mirrors the web builder's shape.
        let bundle = composed.bundle
        XCTAssertEqual(bundle.kbs.count, 2)
        XCTAssertEqual(bundle.kbs.first?.commit, "abc1234")
        XCTAssertTrue(bundle.pages.contains { $0.route == "kb/other-kb/concepts/deep-page" })
    }

    func testCompositionSearch() throws {
        let mini = try loadMini()
        let other = try loadOther()
        let composed = ComposedKB(name: "S", members: [mini, other])
        let hits = composed.search("entity")
        XCTAssertFalse(hits.isEmpty)
        XCTAssertEqual(hits.first?.route, "kb/mini-kb/entity-one")
        XCTAssertTrue(composed.search("zzzz-not-present").isEmpty)
    }

    // MARK: - Themes

    func testBundledThemesResolveTokens() {
        for theme in ReaderTheme.bundled {
            XCTAssertTrue(theme.cssVariables.contains("--amber:"), theme.name)
            XCTAssertTrue(theme.cssVariables.contains("--bg:"), theme.name)
        }
        XCTAssertEqual(ReaderTheme.ink.name, "Ink")
        XCTAssertFalse(ReaderTheme.paper.isDark)
    }

    func testThemeFromPackageYAML() {
        let yaml = """
        name: default
        version: "1.0"
        author: Awesome KB project
        description: The reference theme.
        templates: templates
        assets: assets
        tokens:
          amber: "#ff8800"
        """
        let theme = ReaderTheme.fromThemeYAML(yaml)
        XCTAssertEqual(theme?.name, "default")
        XCTAssertEqual(theme?.token("amber"), "#ff8800")
        // Untouched tokens fall back to defaults.
        XCTAssertEqual(theme?.token("teal"), ReaderTheme.defaults["teal"])
    }

    func testHTMLDocumentShell() {
        let doc = ReaderTheme.ink.htmlDocument(
            title: "T", bodyHTML: "<p>hi</p>",
            provenance: "mini-kb @ abc1234",
            metadata: [(key: "verdict", value: "assessed-candidate")])
        XCTAssertTrue(doc.contains("<style>"))
        XCTAssertTrue(doc.contains("mini-kb @ abc1234"))
        XCTAssertTrue(doc.contains("assessed-candidate"))
        // No pinch/double-tap zoom on rendered pages.
        XCTAssertTrue(doc.contains("user-scalable=no"))
        // External (browser-opening) links are styled apart from internal ones.
        XCTAssertTrue(doc.contains("a[href^=\"https://\"]::after"))
    }

    // MARK: - Library model

    func testCacheName() {
        XCTAssertEqual(
            ReaderLibrary.cacheName(forRemote: "https://github.com/OpenNorms/openshelf-reader.git"),
            "OpenNorms-openshelf-reader")
        XCTAssertEqual(
            ReaderLibrary.cacheName(forRemote: "https://github.com/pier-review/target-discussion"),
            "pier-review-target-discussion")
    }

    func testLibraryCodableRoundTrip() throws {
        var library = ReaderLibrary()
        library.kbs.append(LibraryKB(remoteURL: "https://example.com/a/b.git",
                                     cacheName: "a-b", headSHA: "deadbeef"))
        library.compositions.append(LibraryComposition(name: "C",
                                                       memberCacheNames: ["a-b"]))
        let data = try JSONEncoder().encode(library)
        let decoded = try JSONDecoder().decode(ReaderLibrary.self, from: data)
        XCTAssertEqual(decoded, library)
    }

    func testOldLibraryJSONStillLoads() throws {
        // A library.json from before appearance settings existed.
        let old = """
        {"kbs":[{"remoteURL":"https://example.com/a/b","cacheName":"a-b","headSHA":"abc"}],
         "compositions":[{"name":"C","memberCacheNames":["a-b"]}],
         "globalThemeName":"Chart"}
        """
        let lib = try JSONDecoder().decode(ReaderLibrary.self, from: Data(old.utf8))
        XCTAssertEqual(lib.kbs.count, 1)
        XCTAssertEqual(lib.appearanceMode, .system)
        XCTAssertEqual(lib.typeface, .serif)
        XCTAssertEqual(lib.textSize, 17)
        XCTAssertNil(lib.lastPage)
        // The old global theme (dark) migrates to the dark slot only.
        XCTAssertEqual(lib.darkThemeName, "Chart")
        XCTAssertEqual(lib.lightThemeName, "Paper")
        XCTAssertEqual(lib.readingTheme(dark: true).name, "Chart")

        let light = try JSONDecoder().decode(ReaderLibrary.self,
            from: Data(#"{"kbs":[],"compositions":[],"globalThemeName":"Sepia"}"#.utf8))
        XCTAssertEqual(light.lightThemeName, "Sepia")
        XCTAssertEqual(light.darkThemeName, "Ink")

        // An empty object and an out-of-range size are tolerated too.
        let empty = try JSONDecoder().decode(ReaderLibrary.self, from: Data("{}".utf8))
        XCTAssertEqual(empty, ReaderLibrary())
        let big = try JSONDecoder().decode(ReaderLibrary.self, from: Data(#"{"textSize":99}"#.utf8))
        XCTAssertEqual(big.textSize, 24)
    }

    func testNewLibrarySettingsRoundTrip() throws {
        var lib = ReaderLibrary()
        lib.appearanceMode = .dark
        lib.typeface = .sans
        lib.textSize = 20
        lib.setReadingTheme("Mono", dark: true)
        lib.setReadingTheme("Sepia", dark: false)
        lib.lastPage = LibraryLastPage(kind: .notebook, owner: "a-b", key: "x/y")
        let data = try JSONEncoder().encode(lib)
        XCTAssertEqual(try JSONDecoder().decode(ReaderLibrary.self, from: data), lib)
        XCTAssertEqual(lib.readingTheme(dark: false).name, "Sepia")
    }

    // MARK: - Page CSS settings

    func testPageCSSTypefaceAndSize() {
        let serif = ReaderTheme.ink.pageCSS(typeface: .serif, textSize: 20)
        XCTAssertTrue(serif.contains("--face:var(--serif)"))
        XCTAssertTrue(serif.contains("--fs:20px"))
        XCTAssertTrue(serif.contains("ui-serif"))
        let sans = ReaderTheme.ink.pageCSS(typeface: .sans, textSize: 15)
        XCTAssertTrue(sans.contains("--face:var(--sans)"))
        XCTAssertTrue(sans.contains("--fs:15px"))
        // Out-of-range sizes clamp.
        XCTAssertTrue(ReaderTheme.ink.pageCSS(textSize: 99).contains("--fs:24px"))
        XCTAssertTrue(ReaderTheme.ink.pageCSS(textSize: 3).contains("--fs:14px"))
        let doc = ReaderTheme.paper.htmlDocument(title: "T", bodyHTML: "<p>x</p>",
                                                 typeface: .sans, textSize: 22)
        XCTAssertTrue(doc.contains("--fs:22px") && doc.contains("--face:var(--sans)"))
    }

    func testHTMLDocumentHeaderAndMetadataCard() {
        let doc = ReaderTheme.ink.htmlDocument(
            title: "T", bodyHTML: "<p>body</p>", provenance: "kb @ abc1234",
            metadata: [(key: "status", value: "unknown")],
            header: .init(title: "Page <Title>", summary: "A lede.", chips: ["entity", "stub"]))
        XCTAssertTrue(doc.contains("<span class=\"chip primary\">entity</span>"))
        XCTAssertTrue(doc.contains("<span class=\"chip\">stub</span>"))
        XCTAssertTrue(doc.contains("<h1 class=\"title\">Page &lt;Title&gt;</h1>"))
        XCTAssertTrue(doc.contains("<p class=\"lede\">A lede.</p>"))
        XCTAssertTrue(doc.contains("meta-grid"))
        XCTAssertTrue(doc.contains("<div class=\"meta-k\">Source</div>"))
        XCTAssertTrue(doc.contains("kb @ abc1234"))
    }

    // MARK: - Browsing: categories, A to Z, recency

    func testBrowseGroupsByCategoryThenType() throws {
        let kb = try loadOther()
        let groups = kb.browseGroups
        // Categories first, largest group first.
        XCTAssertEqual(groups.first?.title, "Fuzzing Tools")
        XCTAssertEqual(groups.first?.kind, .category)
        XCTAssertEqual(groups.first?.pages.map(\.slug),
                       ["concepts/deep-page", "concepts/wiki-cross"])
        XCTAssertEqual(groups[1].id, "c:MCU Firmware Fuzzing")
        // The uncategorised page falls back to its type, after categories.
        let last = try XCTUnwrap(groups.last)
        XCTAssertEqual(last.kind, .type)
        XCTAssertEqual(last.id, "t:overview")
        XCTAssertEqual(last.title, "Overview")
        XCTAssertEqual(kb.browseGroup(id: "c:Fuzzing Tools")?.pages.count, 2)
        // Every page is in exactly one group.
        XCTAssertEqual(groups.flatMap(\.pages).count, kb.pages.count)
    }

    func testBrowseGroupsFallBackToTypesWhenNoCategories() throws {
        let kb = try loadMini()
        XCTAssertTrue(kb.browseGroups.allSatisfy { $0.kind == .type })
        XCTAssertEqual(kb.browseGroups.map(\.key), kb.typeGroups.map(\.type))
    }

    func testAtoZAndRecency() throws {
        let kb = try loadOther()
        let titles = kb.pagesAtoZ.map(\.title)
        XCTAssertEqual(titles, titles.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
        // Newest first; undated pages last.
        XCTAssertEqual(kb.pagesByRecency.prefix(3).map(\.slug),
                       ["concepts/wiki-cross", "concepts/deep-page", "tools/fuzzware"])
        XCTAssertEqual(kb.pagesByRecency.last?.slug, "overview")
    }

    // MARK: - Search scopes and highlighting

    func testSearchTitlesOnlyAndScope() throws {
        let mini = try loadMini()
        let other = try loadOther()
        let composed = ComposedKB(name: "S", members: [mini, other])
        // "fuzz" appears in titles and bodies of other-kb pages only.
        let all = composed.search("fuzz")
        XCTAssertTrue(all.allSatisfy { $0.kbID == "other-kb" })
        let titles = composed.search("fuzz", titlesOnly: true)
        XCTAssertEqual(titles.map(\.title), ["Fuzzware"])
        // "details" is in a body, not a title.
        XCTAssertFalse(composed.search("fuzzing").isEmpty)
        XCTAssertTrue(composed.search("entity", titlesOnly: true, kbIDs: ["other-kb"]).isEmpty)
        XCTAssertFalse(composed.search("entity", kbIDs: ["mini-kb"]).isEmpty)
        let fw = try XCTUnwrap(all.first(where: { $0.title == "Fuzzware" }))
        XCTAssertEqual(fw.category, "MCU Firmware Fuzzing")
        // Category falls back to type.
        let overview = try XCTUnwrap(composed.search("overview").first(where: { $0.route == "kb/mini-kb/overview" }))
        XCTAssertEqual(overview.category, "overview")
    }

    func testSearchHighlightSegments() {
        let segs = SearchHighlight.segments("GDBFuzz and fuzzing", query: "fuzz")
        XCTAssertEqual(segs, [
            .init(text: "GDB", matched: false), .init(text: "Fuzz", matched: true),
            .init(text: " and ", matched: false), .init(text: "fuzz", matched: true),
            .init(text: "ing", matched: false)])
        XCTAssertEqual(SearchHighlight.segments("abc", query: "  "),
                       [.init(text: "abc", matched: false)])
        XCTAssertEqual(SearchHighlight.segments("abc", query: "z"),
                       [.init(text: "abc", matched: false)])
        XCTAssertEqual(SearchHighlight.segments("", query: "z"), [])
        XCTAssertEqual(SearchHighlight.segments("Café", query: "cafe").first?.matched, true)
    }

    // MARK: - Headings and page body

    func testOutlineAndHeadingIDs() throws {
        let kb = try loadOther()
        let page = try XCTUnwrap(kb.page(slug: "tools/fuzzware"))
        let outline = Markdown.outline(page.body)
        XCTAssertEqual(outline.map(\.id), ["fuzzware", "why-it-matters", "why-it-matters-1"])
        XCTAssertEqual(outline.map(\.level), [1, 2, 2])
        // The rendered ids match the outline's.
        let html = Notebook(kb: kb).renderHTML(page)
        XCTAssertTrue(html.contains("<h2 id=\"why-it-matters-1\">"), html)
        // Markup is stripped; fenced "headings" are ignored.
        let items = Markdown.outline("## A `b` [c](d)\n```\n# not a heading\n```\n### **Bold** end")
        XCTAssertEqual(items.map(\.text), ["A b c", "Bold end"])
        XCTAssertEqual(items.map(\.id), ["a-b-c", "bold-end"])
    }

    func testLeadingTitleIsDroppedOnlyWhenItRepeatsTheTitle() throws {
        let kb = try loadOther()
        let page = try XCTUnwrap(kb.page(slug: "tools/fuzzware"))
        XCTAssertFalse(page.bodyWithoutLeadingTitle.contains("# Fuzzware"))
        let html = Notebook(kb: kb).renderHTML(page, dropLeadingTitle: true)
        XCTAssertFalse(html.contains("<h1"), html)
        // A different leading heading stays.
        let overview = try XCTUnwrap(kb.page(slug: "overview"))
        XCTAssertEqual(overview.bodyWithoutLeadingTitle.contains("# Other overview"), false)
        let other = KBPage(slug: "x", relativePath: "x.md",
                           markdown: "---\ntitle: Real\n---\n# Different\ntext")
        XCTAssertTrue(other.bodyWithoutLeadingTitle.contains("# Different"))
    }

    func testManifestVersionAndLicense() throws {
        let kb = try loadOther()
        XCTAssertEqual(kb.manifest.version, "2026.11.01")
        XCTAssertEqual(kb.manifest.license, "CC0-1.0")
    }

    func testCoverPaletteIndexIsStable() {
        XCTAssertEqual(coverPaletteIndex(for: "mini-kb", paletteSize: 6),
                       coverPaletteIndex(for: "mini-kb", paletteSize: 6))
        // Pinned value: the hash must not change between runs or builds.
        XCTAssertEqual(coverPaletteIndex(for: "a", paletteSize: 1000), Int((0xaf63dc4c8601ec8c as UInt64) % 1000))
        let used = Set(["a", "b", "c", "d", "e", "f", "g", "h"].map {
            coverPaletteIndex(for: $0, paletteSize: 6)
        })
        XCTAssertTrue(used.count > 1)
        XCTAssertTrue(used.allSatisfy { (0..<6).contains($0) })
        XCTAssertEqual(coverPaletteIndex(for: "x", paletteSize: 0), 0)
    }

    // MARK: - YAML subset

    func testYAMLSubsetShapes() {
        let pairs = YAMLSubset.parse("""
        title: "Quoted: Title"
        count: 42
        tags: [one, two]
        nested:
          inner: value
          deep:
            leaf: yes
        items:
          - name: first
            v: 1
          - name: second
            v: 2
        """)
        let root = YAMLValue.map(pairs)
        XCTAssertEqual(root.string(forKey: "title"), "Quoted: Title")
        XCTAssertEqual(root.string(forKey: "count"), "42")
        XCTAssertEqual(root.stringList(forKey: "tags"), ["one", "two"])
        XCTAssertEqual(root.value(forKey: "nested")?
            .value(forKey: "deep")?.string(forKey: "leaf"), "yes")
        let items = root.value(forKey: "items")?.listValue
        XCTAssertEqual(items?.count, 2)
        XCTAssertEqual(items?.first?.string(forKey: "name"), "first")
    }

    // MARK: Landing page

    func testLatestLogEntryAndOverview() throws {
        let kb = try loadMini()
        XCTAssertEqual(kb.overviewPage?.relativePath, "index.md")
        XCTAssertEqual(kb.latestLogEntry,
                       KnowledgeBase.LogEntry(date: "2026-11-11", kind: "ingest", title: "fixture created"))
    }

    func testGeneratedIndexPagesAreNotListed() {
        let generated = KBPage(slug: "index-fuzzing-tools", relativePath: "wiki/index-fuzzing-tools.md",
                               markdown: "# Fuzzing Tools\n\n- [AFL](afl.md)\n")
        let authored = KBPage(slug: "index-cards", relativePath: "wiki/index-cards.md",
                              markdown: "---\ntitle: Index cards\n---\nBody\n")
        XCTAssertTrue(KnowledgeBase.isGeneratedIndex(generated))
        XCTAssertFalse(KnowledgeBase.isGeneratedIndex(authored))
    }

    func testSlugsAddedAndRecents() throws {
        let kb = try loadMini()
        let all = Set(kb.pages.map(\.slug))
        XCTAssertEqual(kb.slugsAdded(since: all), [])
        XCTAssertEqual(kb.slugsAdded(since: all.subtracting(["entity-one"])), ["entity-one"])

        var entry = LibraryKB(remoteURL: "https://example.org/a/b", cacheName: "a-b")
        entry.noteOpened("one"); entry.noteOpened("two"); entry.noteOpened("one")
        XCTAssertEqual(entry.recentSlugs, ["one", "two"])
        let decoded = try JSONDecoder().decode(
            LibraryKB.self, from: Data(#"{"remoteURL":"u","cacheName":"c"}"#.utf8))
        XCTAssertNil(decoded.recentSlugs)

        XCTAssertEqual(KBManifest(pairs: YAMLSubset.parse("title: \"Embedded Security (Awesome KB)\""),
                                  fallbackID: "x").shortTitle, "Embedded Security")
    }
}
