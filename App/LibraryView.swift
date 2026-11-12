import SwiftUI
import ReaderCore

/// The library: notebooks (individual KBs) and composed KBs, plus the
/// add / compose / theme sheets. Owns the app's one NavigationStack.
struct LibraryView: View {
    @EnvironmentObject var store: KBStore
    @State private var path: [Route] = []
    @State private var showAddKB = false
    @State private var showCompose = false
    @State private var showThemes = false

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section("Notebooks") {
                    ForEach(store.library.kbs, id: \.cacheName) { entry in
                        NavigationLink(value: Route.notebook(entry.cacheName)) {
                            KBRow(entry: entry, kb: store.loaded[entry.cacheName],
                                  syncing: store.syncing.contains(entry.cacheName))
                        }
                        .swipeActions {
                            Button("Pull") {
                                Task { await store.pull(entry) }
                            }
                            Button("Remove", role: .destructive) {
                                store.removeKB(entry.cacheName)
                            }
                        }
                    }
                }
                Section("Composed") {
                    ForEach(store.library.compositions, id: \.name) { comp in
                        NavigationLink(value: Route.composition(comp.name)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(comp.name).font(.headline)
                                Text(comp.memberCacheNames.joined(separator: " + "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions {
                            Button("Delete", role: .destructive) {
                                store.removeComposition(comp.name)
                            }
                        }
                    }
                }
                if let error = store.lastError {
                    Section {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("OpenShelf Reader")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showAddKB = true } label: {
                        Label("Add KB", systemImage: "plus.circle")
                    }
                    Button { showCompose = true } label: {
                        Label("Compose", systemImage: "square.stack.3d.up")
                    }
                    .disabled(store.library.kbs.count < 2)
                    Button { showThemes = true } label: {
                        Label("Themes", systemImage: "paintpalette")
                    }
                }
            }
            .refreshable { await store.pullAll() }
            .navigationDestination(for: Route.self) { route in
                destination(route)
            }
            .sheet(isPresented: $showAddKB) { AddKBView() }
            .sheet(isPresented: $showCompose) { ComposeView() }
            .sheet(isPresented: $showThemes) { ThemesView() }
        }
    }

    @ViewBuilder
    private func destination(_ route: Route) -> some View {
        switch route {
        case .notebook(let cacheName):
            NotebookView(cacheName: cacheName) { slug in
                path.append(.page(cacheName, slug))
            }
        case .page(let cacheName, let slug):
            notebookPage(cacheName: cacheName, slug: slug)
        case .composition(let name):
            ComposedView(name: name) { composedRoute in
                path.append(.composedPage(name, composedRoute))
            }
        case .composedPage(let name, let composedRoute):
            composedPage(name: name, route: composedRoute)
        }
    }

    @ViewBuilder
    private func notebookPage(cacheName: String, slug: String) -> some View {
        if let kb = store.loaded[cacheName], let page = kb.page(slug: slug) {
            PageReaderView(
                title: page.title,
                fragmentHTML: Notebook(kb: kb).renderHTML(page),
                theme: store.theme(for: cacheName),
                provenance: "\(kb.id) @ \(shortSHA(kb.headSHA))",
                metadata: page.metadataPairs,
                verdict: page.verdict,
                fileURL: { kbID, path in
                    store.loaded.values.first(where: { $0.id == kbID })
                        .map { $0.directory.appendingPathComponent(String(path.dropFirst())) }
                },
                onRoute: { route in
                    if route.hasPrefix("page/") {
                        path.append(.page(cacheName, String(route.dropFirst(5))))
                    }
                })
        } else {
            ContentUnavailableView("Page not loaded",
                                   systemImage: "doc.questionmark")
        }
    }

    @ViewBuilder
    private func composedPage(name: String, route: String) -> some View {
        if let comp = store.library.compositions.first(where: { $0.name == name }),
           let composed = store.composedKB(comp),
           let target = composed.page(route: route) {
            PageReaderView(
                title: target.page.title,
                fragmentHTML: composed.renderHTML(target),
                theme: store.globalTheme,
                provenance: "\(target.kbID) @ \(shortSHA(composed.pin(for: target.kbID)))",
                metadata: target.page.metadataPairs,
                verdict: target.page.verdict,
                fileURL: { kbID, path in
                    composed.member(id: kbID)
                        .map { $0.directory.appendingPathComponent(String(path.dropFirst())) }
                },
                onRoute: { next in
                    if next.hasPrefix("kb/") {
                        path.append(.composedPage(name, next))
                    }
                })
        } else {
            ContentUnavailableView("Page not loaded",
                                   systemImage: "doc.questionmark")
        }
    }
}

func shortSHA(_ sha: String?) -> String {
    guard let sha else { return "unpinned" }
    return String(sha.prefix(7))
}

private struct KBRow: View {
    var entry: LibraryKB
    var kb: KnowledgeBase?
    var syncing: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(kb?.title ?? entry.cacheName).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if syncing { ProgressView() }
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if let kb { parts.append("\(kb.pages.count) pages") }
        parts.append("@ \(shortSHA(entry.headSHA))")
        if let pulled = entry.lastPulled {
            let date = Date(timeIntervalSince1970: pulled)
            parts.append("pulled \(date.formatted(date: .abbreviated, time: .shortened))")
        } else {
            parts.append("not pulled yet")
        }
        return parts.joined(separator: " · ")
    }
}

private struct AddKBView: View {
    @EnvironmentObject var store: KBStore
    @Environment(\.dismiss) var dismiss
    @State private var url = ""
    @State private var branch = ""
    @State private var token = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Git URL (https://github.com/…)", text: $url)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Branch (optional)", text: $branch)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Access token for private repos (optional)",
                            text: $token)
                Text("The repository is cloned into the reader's local cache and synced with Git pulls. The cache is read-only.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .navigationTitle("Add knowledge base")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let u = url, b = branch, t = token
                        dismiss()
                        Task {
                            await store.addKB(
                                remoteURL: u,
                                branch: b.isEmpty ? nil : b,
                                token: t.isEmpty ? nil : t)
                        }
                    }.disabled(url.isEmpty)
                }
            }
        }
    }
}

private struct ComposeView: View {
    @EnvironmentObject var store: KBStore
    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @State private var selected: Set<String> = []

    var body: some View {
        NavigationStack {
            Form {
                TextField("Composition name", text: $name)
                Section("Member knowledge bases") {
                    ForEach(store.library.kbs, id: \.cacheName) { entry in
                        Toggle(store.loaded[entry.cacheName]?.title ?? entry.cacheName,
                               isOn: Binding(
                                get: { selected.contains(entry.cacheName) },
                                set: { on in
                                    if on { selected.insert(entry.cacheName) }
                                    else { selected.remove(entry.cacheName) }
                                }))
                    }
                }
                Text("A composed KB renders its members as one corpus: unified browsing and search, cross-KB links resolved, every page keeping its source KB and commit as provenance.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .navigationTitle("New composition")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        store.addComposition(name: name,
                                             memberCacheNames: Array(selected))
                        dismiss()
                    }.disabled(name.isEmpty || selected.count < 2)
                }
            }
        }
    }
}

private struct ThemesView: View {
    @EnvironmentObject var store: KBStore
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List(ReaderTheme.bundled, id: \.name) { theme in
                Button {
                    store.setGlobalTheme(theme.name)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(theme.name).foregroundStyle(.primary)
                            Text(theme.isDark ? "Dark" : "Light")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if store.library.globalThemeName == theme.name {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            .navigationTitle("Theme")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
