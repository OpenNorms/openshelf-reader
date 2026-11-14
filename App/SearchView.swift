import SwiftUI
import ReaderCore

/// A-Search: one search across all loaded notebooks, with scope chips.
struct SearchView: View {
    @EnvironmentObject var store: KBStore
    @Environment(\.palette) private var pal
    @Environment(\.dismiss) private var dismiss
    var initialScope: String?
    @State private var query = ""
    @State private var scope: String?          // cacheName; nil = all shelves
    @State private var titlesOnly = false
    @State private var didSetup = false
    @FocusState private var focused: Bool

    private var notebooks: [(cacheName: String, kb: KnowledgeBase)] {
        store.library.kbs.compactMap { e in store.loaded[e.cacheName].map { (e.cacheName, $0) } }
    }

    private var hits: [ComposedKB.SearchHit] {
        let kbs = notebooks.map(\.kb)
        let ids: Set<String>? = scope.flatMap { store.loaded[$0] }.map { [$0.id] }
        return ComposedKB(name: "search", members: kbs)
            .search(query, titlesOnly: titlesOnly, kbIDs: ids)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                HStack(spacing: 10) {
                    IconView(icon: .search, size: 18, lineWidth: 2).foregroundStyle(pal.accent)
                    TextField("", text: $query, prompt: Text("Search").foregroundStyle(pal.faint))
                        .focused($focused)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .submitLabel(.search)
                        .uiFont(17).foregroundStyle(pal.ink)
                        .accessibilityLabel("Search")
                    if !query.isEmpty {
                        Button { query = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(pal.faint)
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Clear search")
                    }
                }
                .padding(.leading, 14).padding(.trailing, query.isEmpty ? 14 : 0)
                .frame(minHeight: 48)
                .background(RoundedRectangle(cornerRadius: 16).fill(pal.panel))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(pal.accent, lineWidth: 1.5))
                Button("Cancel") { dismiss() }
                    .uiFont(15, style: .callout).foregroundStyle(pal.accent)
                    .frame(minHeight: 44)
            }
            .padding(.horizontal, 20).padding(.top, 8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    PillChip(title: "All shelves", selected: scope == nil) { scope = nil }
                    ForEach(notebooks, id: \.cacheName) { nb in
                        PillChip(title: nb.kb.title, selected: scope == nb.cacheName, leading: {
                            UnevenRoundedRectangle(topLeadingRadius: 1, bottomLeadingRadius: 1,
                                                   bottomTrailingRadius: 3, topTrailingRadius: 3)
                                .fill(CoverStyle.forID(nb.kb.id).chip).frame(width: 9, height: 13)
                        }) { scope = nb.cacheName }
                    }
                    PillChip(title: "Titles only", selected: titlesOnly) { titlesOnly.toggle() }
                }
                .padding(.horizontal, 20)
            }
            .padding(.top, 14)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) { content }
                    .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 60)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(pal.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            if !didSetup { didSetup = true; scope = initialScope; focused = true }
        }
    }

    @ViewBuilder
    private var content: some View {
        if notebooks.isEmpty {
            note("Nothing to search yet", "Add and pull a notebook first.")
        } else if query.trimmingCharacters(in: .whitespaces).isEmpty {
            let scopeCount = scope == nil ? notebooks.count : 1
            note("Search your shelves",
                 "Across \(scopeCount) notebook\(scopeCount == 1 ? "" : "s"): titles, summaries and page text.")
        } else {
            let found = hits
            if found.isEmpty {
                note("No matches", "Nothing for “\(query)”\(titlesOnly ? " in titles" : "").")
            } else {
                ForEach(Array(found.enumerated()), id: \.element.route) { i, hit in
                    if let cache = store.cacheName(forKBID: hit.kbID) {
                        let slug = String(hit.route.dropFirst("kb/\(hit.kbID)/".count))
                        NavigationLink(value: Route.page(cache, slug)) {
                            SearchResultRow(title: hit.title, summary: hit.summary,
                                            provenance: hit.category,
                                            notebookStyle: CoverStyle.forID(hit.kbID),
                                            notebookTitle: scope == nil ? store.loaded[cache]?.title : nil,
                                            query: query)
                        }
                        .buttonStyle(.plain)
                        if i < found.count - 1 { RowDivider() }
                    }
                }
            }
        }
    }

    private func note(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).displayFont(22, style: .title3).foregroundStyle(pal.ink)
            Text(detail).uiFont(14, style: .subheadline).foregroundStyle(pal.dim)
        }
        .padding(.top, 24)
    }
}
