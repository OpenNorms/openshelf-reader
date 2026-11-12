import SwiftUI
import ReaderCore

/// One KB on its own — the notebook case. Pages grouped by type, with
/// in-KB search; the toolbar pulls this KB and sets its theme override.
struct NotebookView: View {
    @EnvironmentObject var store: KBStore
    var cacheName: String
    var openPage: (String) -> Void
    @State private var query = ""

    private var kb: KnowledgeBase? { store.loaded[cacheName] }
    private var entry: LibraryKB? {
        store.library.kbs.first(where: { $0.cacheName == cacheName })
    }

    var body: some View {
        Group {
            if let kb {
                List {
                    if query.isEmpty {
                        ForEach(kb.typeGroups, id: \.type) { group in
                            Section(group.type.capitalized) {
                                ForEach(group.pages, id: \.slug) { page in
                                    PageRow(page: page) { openPage(page.slug) }
                                }
                            }
                        }
                    } else {
                        let composed = ComposedKB(name: kb.id, members: [kb])
                        ForEach(composed.search(query), id: \.route) { hit in
                            Button {
                                openPage(String(hit.route.dropFirst("kb/\(kb.id)/".count)))
                            } label: {
                                SearchRow(title: hit.title, summary: hit.summary)
                            }
                        }
                    }
                }
                .searchable(text: $query, prompt: "Search this KB")
            } else {
                ContentUnavailableView("Not pulled yet",
                                       systemImage: "arrow.down.circle",
                                       description: Text("Pull to clone this repository into the local cache."))
            }
        }
        .navigationTitle(kb?.title ?? cacheName)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if let entry {
                    Button {
                        Task { await store.pull(entry) }
                    } label: {
                        Label("Pull", systemImage: "arrow.clockwise")
                    }
                }
                Menu {
                    Button("Use global theme") {
                        store.setTheme(nil, for: cacheName)
                    }
                    ForEach(ReaderTheme.bundled, id: \.name) { theme in
                        Button(theme.name) {
                            store.setTheme(theme.name, for: cacheName)
                        }
                    }
                } label: {
                    Label("Theme", systemImage: "paintpalette")
                }
            }
        }
    }
}

struct PageRow: View {
    var page: KBPage
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(page.title).foregroundStyle(.primary)
                if let summary = page.summary {
                    Text(summary).font(.caption).foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if let verdict = page.verdict {
                    Text(verdict).font(.caption2).foregroundStyle(.orange)
                }
            }
        }
    }
}

struct SearchRow: View {
    var title: String
    var summary: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).foregroundStyle(.primary)
            if let summary {
                Text(summary).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }
}
