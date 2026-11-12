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
        XCTAssertTrue(html.contains("<h1>Title</h1>"), html)
        XCTAssertTrue(html.contains("<strong>bold</strong>"), html)
        XCTAssertTrue(html.contains("<em>italic</em>"), html)
        XCTAssertTrue(html.contains("<code>code</code>"), html)
        XCTAssertTrue(html.contains("<li>one</li>"), html)
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
}
