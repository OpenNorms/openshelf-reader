import SwiftUI
import ReaderCore

/// The app's one NavigationStack: the library home plus every screen
/// pushed from it, the forward stack, and the add / compose / appearance /
/// token sheets.
struct LibraryView: View {
    @EnvironmentObject var store: KBStore
    @Environment(\.colorScheme) private var scheme
    @Environment(\.palette) private var pal
    @State private var path: [Route] = []
    /// Pages left by going back, most recent last — what "forward" re-opens.
    /// Following a new link clears it, as in a browser.
    @State private var forward: [Route] = []
    @State private var goingForward = false
    @State private var sheet: ActiveSheet?

    enum ActiveSheet: Identifiable {
        case add, compose, appearance(AppearanceContext), token(String)
        var id: String {
            switch self {
            case .add: return "add"
            case .compose: return "compose"
            case .appearance(let c): return "appearance-\(c.id)"
            case .token(let n): return "token-\(n)"
            }
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            LibraryHome(
                onAdd: { sheet = .add },
                onCompose: { sheet = .compose },
                onSearch: { path.append(.search(nil)) },
                onAppearance: { sheet = .appearance(AppearanceContext(cacheName: nil)) },
                onUpdateToken: { sheet = .token($0) })
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Route.self) { route in
                destination(route)
            }
        }
        .tint(pal.accent)
        .onChange(of: path) { old, new in
            rememberLastPage(new.last)
            if goingForward { goingForward = false; return }
            if new.count < old.count, Array(old.prefix(new.count)) == new {
                // Popped (swipe, back button or edge gesture): remember
                // what was left, nearest page on top.
                forward.append(contentsOf: old[new.count...].reversed())
            } else {
                forward.removeAll()
            }
        }
        .sheet(item: $sheet) { sheet in
            Group {
                switch sheet {
                case .add: AddKBSheet()
                case .compose: ComposeSheet()
                case .appearance(let context): AppearanceSheet(context: context)
                case .token(let name): UpdateTokenSheet(cacheName: name)
                }
            }
            .environmentObject(store)
            .environment(\.typeface, store.library.typeface)
            .preferredColorScheme(store.preferredScheme)
        }
    }

    private func rememberLastPage(_ route: Route?) {
        switch route {
        case .page(let cache, let slug):
            store.setLastPage(LibraryLastPage(kind: .notebook, owner: cache, key: slug))
            store.noteOpened(cacheName: cache, slug: slug)
        case .composedPage(let name, let key):
            store.setLastPage(LibraryLastPage(kind: .composed, owner: name, key: key))
        default: break
        }
    }

    // MARK: Navigation

    private func handleSwipe(_ direction: ReaderWebView.SwipeDirection) {
        switch direction {
        case .back:
            if !path.isEmpty { path.removeLast() }
        case .forward:
            goForward()
        }
    }

    private func goForward() {
        guard let next = forward.popLast() else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        goingForward = true
        path.append(next)
    }

    @ViewBuilder
    private func destination(_ route: Route) -> some View {
        switch route {
        case .notebook(let cacheName):
            NotebookView(cacheName: cacheName,
                         onAppearance: { sheet = .appearance(AppearanceContext(cacheName: cacheName)) },
                         onOpen: { path.append($0) })
        case .list(let cacheName, let kind):
            PageListView(cacheName: cacheName, kind: PageListView.Kind(rawValue: kind) ?? .az)
        case .group(let cacheName, let groupID):
            GroupView(cacheName: cacheName, groupID: groupID)
        case .page(let cacheName, let slug):
            notebookPage(cacheName: cacheName, slug: slug)
        case .composition(let name):
            ComposedView(name: name) { sheet = .appearance(AppearanceContext(cacheName: nil)) }
        case .composedPage(let name, let composedRoute):
            composedPage(name: name, route: composedRoute)
        case .search(let scope):
            SearchView(initialScope: scope)
        }
    }

    private func chips(_ page: KBPage) -> [String] {
        [page.type, page.depth, page.verdict].compactMap { $0 }
    }

    @ViewBuilder
    private func notebookPage(cacheName: String, slug: String) -> some View {
        if let kb = store.loaded[cacheName], let page = kb.page(slug: slug) {
            PageReaderView(
                content: PageContent(
                    pageID: "nb:\(cacheName)/\(slug)",
                    title: page.title, summary: page.summary, chips: chips(page),
                    fragmentHTML: Notebook(kb: kb).renderHTML(page, dropLeadingTitle: true),
                    headings: Markdown.outline(page.bodyWithoutLeadingTitle),
                    provenance: "\(kb.id) @ \(shortSHA(kb.headSHA))",
                    metadata: page.metadataPairs,
                    contextLabel: page.category ?? kb.title),
                theme: store.theme(for: cacheName, dark: scheme == .dark),
                typeface: store.library.typeface, textSize: store.library.textSize,
                fileURL: { kbID, path in
                    store.loaded.values.first(where: { $0.id == kbID })
                        .map { $0.directory.appendingPathComponent(String(path.dropFirst())) }
                },
                onRoute: { route in
                    if route.hasPrefix("page/") {
                        path.append(.page(cacheName, String(route.dropFirst(5))))
                    }
                },
                onSwipe: handleSwipe,
                canGoForward: !forward.isEmpty,
                onForward: goForward,
                onSearch: { path.append(.search(cacheName)) },
                onLibrary: { path.removeAll() },
                onAppearance: { sheet = .appearance(AppearanceContext(cacheName: cacheName)) })
        } else {
            missingPage
        }
    }

    @ViewBuilder
    private func composedPage(name: String, route: String) -> some View {
        if let comp = store.library.compositions.first(where: { $0.name == name }),
           let composed = store.composedKB(comp),
           let target = composed.page(route: route) {
            PageReaderView(
                content: PageContent(
                    pageID: "co:\(name)/\(route)",
                    title: target.page.title, summary: target.page.summary,
                    chips: chips(target.page),
                    fragmentHTML: composed.renderHTML(target, dropLeadingTitle: true),
                    headings: Markdown.outline(target.page.bodyWithoutLeadingTitle),
                    provenance: "\(target.kbID) @ \(shortSHA(composed.pin(for: target.kbID)))",
                    metadata: target.page.metadataPairs,
                    contextLabel: target.page.category ?? name),
                theme: store.library.readingTheme(dark: scheme == .dark),
                typeface: store.library.typeface, textSize: store.library.textSize,
                fileURL: { kbID, path in
                    composed.member(id: kbID)
                        .map { $0.directory.appendingPathComponent(String(path.dropFirst())) }
                },
                onRoute: { next in
                    if next.hasPrefix("kb/") {
                        path.append(.composedPage(name, next))
                    }
                },
                onSwipe: handleSwipe,
                canGoForward: !forward.isEmpty,
                onForward: goForward,
                onSearch: { path.append(.search(nil)) },
                onLibrary: { path.removeAll() },
                onAppearance: { sheet = .appearance(AppearanceContext(cacheName: nil)) })
        } else {
            missingPage
        }
    }

    private var missingPage: some View {
        VStack(spacing: 12) {
            Text("Page not loaded").displayFont(24, style: .title2).foregroundStyle(pal.ink)
            Text("It may have been removed by the latest pull.")
                .uiFont(15, style: .callout).foregroundStyle(pal.dim)
            Button("Back to library") { path.removeAll() }
                .uiFont(15, weight: .semibold).foregroundStyle(pal.accent).frame(minHeight: 44)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(pal.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }
}

func shortSHA(_ sha: String?) -> String {
    guard let sha else { return "unpinned" }
    return String(sha.prefix(7))
}
