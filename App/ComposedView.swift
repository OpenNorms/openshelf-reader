import SwiftUI
import ReaderCore

/// A composed KB: its members rendered as one corpus. Browsing is
/// grouped by member KB (provenance stays visible); search runs across
/// the whole composition.
struct ComposedView: View {
    @EnvironmentObject var store: KBStore
    var name: String
    var openComposedPage: (String) -> Void
    @State private var query = ""

    private var composition: LibraryComposition? {
        store.library.compositions.first(where: { $0.name == name })
    }

    private var composed: ComposedKB? {
        composition.flatMap { store.composedKB($0) }
    }

    var body: some View {
        Group {
            if let composed {
                List {
                    if query.isEmpty {
                        ForEach(composed.members, id: \.id) { member in
                            Section {
                                ForEach(member.pages, id: \.slug) { page in
                                    PageRow(page: page) {
                                        openComposedPage("kb/\(member.id)/\(page.slug)")
                                    }
                                }
                            } header: {
                                Text("\(member.title) · @ \(shortSHA(member.headSHA))")
                            }
                        }
                    } else {
                        ForEach(composed.search(query), id: \.route) { hit in
                            Button { openComposedPage(hit.route) } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    SearchRow(title: hit.title, summary: hit.summary)
                                    Text(hit.kbID).font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .searchable(text: $query, prompt: "Search the composition")
            } else {
                ContentUnavailableView(
                    "Members not loaded",
                    systemImage: "square.stack.3d.up.slash",
                    description: Text("Pull each member KB from the library first."))
            }
        }
        .navigationTitle(name)
    }
}
