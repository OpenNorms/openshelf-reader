import SwiftUI
import ReaderCore

/// A composed KB, in the notebook's visual language: its members read as
/// one corpus. Browsing is grouped by member KB (provenance stays
/// visible); search runs across the whole composition.
struct ComposedView: View {
    @EnvironmentObject var store: KBStore
    @Environment(\.palette) private var pal
    var name: String
    var onAppearance: () -> Void
    @State private var query = ""

    private var composition: LibraryComposition? {
        store.library.compositions.first(where: { $0.name == name })
    }
    private var composed: ComposedKB? { composition.flatMap { store.composedKB($0) } }

    var body: some View {
        VStack(spacing: 0) {
            ScreenBar(tint: pal.ink) {
                BarButton(tint: pal.ink, label: "Appearance",
                          content: AnyView(Text("Aa").displayFont(20, weight: .regular)),
                          action: onAppearance)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    header
                    if let composed {
                        SearchField(text: $query, prompt: "Search the composition")
                            .padding(.horizontal, 20).padding(.top, 16)
                        if query.trimmingCharacters(in: .whitespaces).isEmpty {
                            ForEach(composed.members, id: \.id) { member in
                                Section {
                                    ForEach(Array(member.pagesAtoZ.enumerated()), id: \.element.slug) { i, page in
                                        NavigationLink(value: Route.composedPage(name, "kb/\(member.id)/\(page.slug)")) {
                                            PageListRow(page: page, detail: nil)
                                        }
                                        .buttonStyle(.plain)
                                        .padding(.horizontal, 20)
                                        if i < member.pages.count - 1 { RowDivider().padding(.horizontal, 20) }
                                    }
                                } header: {
                                    memberHeader(member)
                                }
                            }
                        } else {
                            results(composed)
                        }
                    } else {
                        VStack(spacing: 12) {
                            Text("Members not loaded").displayFont(24, style: .title2).foregroundStyle(pal.ink)
                            Text("Pull each member notebook from the library first.")
                                .uiFont(15, style: .callout).foregroundStyle(pal.dim).multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity).padding(.top, 60).padding(.horizontal, 20)
                    }
                }
                .padding(.bottom, 60)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(pal.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        let members = composition?.memberCacheNames ?? []
        let styleA = CoverStyle.forID(store.coverKey(forCacheName: members.first ?? name))
        let styleB = CoverStyle.forID(store.coverKey(forCacheName: members.dropFirst().first ?? name))
        return HStack(alignment: .bottom, spacing: 18) {
            StackedCovers(back: styleB, front: styleA, scale: 1.25)
            VStack(alignment: .leading, spacing: 6) {
                Text("COMPOSED").monoFont(10, style: .caption2).tracking(1.2).foregroundStyle(pal.accent)
                Text(name).displayFont(34, style: .largeTitle).foregroundStyle(pal.ink)
                    .lineSpacing(-3).accessibilityAddTraits(.isHeader)
                Text(members.map { store.loaded[$0]?.title ?? $0 }.joined(separator: " + "))
                    .uiFont(13, style: .footnote).foregroundStyle(pal.dim)
                if let composed {
                    Text("\(composed.pages.count) pages · \(composed.members.count) notebooks")
                        .uiFont(13, style: .footnote).foregroundStyle(pal.faint)
                }
            }
        }
        .padding(.horizontal, 20).padding(.top, 8)
    }

    private func memberHeader(_ member: KnowledgeBase) -> some View {
        let cacheName = store.cacheName(forKBID: member.id) ?? member.id
        return HStack(spacing: 10) {
            MiniCover(style: CoverStyle.forID(store.coverKey(forCacheName: cacheName)),
                      width: 14, height: 20, spine: 2)
            Text(member.title).displayFont(17, style: .headline).foregroundStyle(pal.ink).lineLimit(1)
            Spacer(minLength: 8)
            Text("\(member.pages.count) · @ \(shortSHA(member.headSHA))")
                .monoFont(11, style: .caption2).foregroundStyle(pal.faint)
        }
        .padding(.horizontal, 20).padding(.vertical, 10).frame(minHeight: 44)
        .background(pal.bg)
        .overlay(alignment: .bottom) { Rectangle().fill(pal.line).frame(height: 1) }
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private func results(_ composed: ComposedKB) -> some View {
        let hits = composed.search(query)
        if hits.isEmpty {
            Text("No pages match “\(query)”.").uiFont(15, style: .callout)
                .foregroundStyle(pal.dim).padding(.top, 24).padding(.horizontal, 20)
        } else {
            ForEach(Array(hits.enumerated()), id: \.element.route) { i, hit in
                NavigationLink(value: Route.composedPage(name, hit.route)) {
                    SearchResultRow(
                        title: hit.title, summary: hit.summary, provenance: hit.category,
                        notebookStyle: CoverStyle.forID(hit.kbID),
                        notebookTitle: composed.member(id: hit.kbID)?.title, query: query)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                if i < hits.count - 1 { RowDivider().padding(.horizontal, 20) }
            }
        }
    }
}
