import SwiftUI
import ReaderCore

/// Shared pieces of the notebook, group and composed screens.
struct SearchField: View {
    @Environment(\.palette) private var pal
    @Binding var text: String
    var prompt: String
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            IconView(icon: .search, size: 18).foregroundStyle(focused ? pal.accent : pal.faint)
            TextField("", text: $text, prompt: Text(prompt).foregroundStyle(pal.faint))
                .focused($focused)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .submitLabel(.search)
                .uiFont(15, style: .callout).foregroundStyle(pal.ink)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(pal.faint)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, 14).padding(.trailing, text.isEmpty ? 14 : 0)
        .frame(minHeight: 46)
        .background(RoundedRectangle(cornerRadius: 14).fill(pal.panel))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .stroke(focused ? pal.accent : pal.line, lineWidth: focused ? 1.5 : 1))
    }
}

/// A search result: highlighted title and summary, then a provenance line
/// (category or type, and the notebook as a cover-colour chip).
struct SearchResultRow: View {
    @Environment(\.palette) private var pal
    var title: String
    var summary: String?
    var provenance: String?
    var notebookStyle: CoverStyle?
    var notebookTitle: String?
    var query: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HighlightedText(text: title, query: query)
                .displayFont(21, style: .title3).foregroundStyle(pal.ink)
                .lineLimit(2).multilineTextAlignment(.leading)
            if let summary, !summary.isEmpty {
                HighlightedText(text: summary, query: query)
                    .uiFont(14, style: .subheadline).foregroundStyle(pal.dim)
                    .lineSpacing(2).lineLimit(3).multilineTextAlignment(.leading)
            }
            HStack(spacing: 8) {
                if let notebookStyle {
                    UnevenRoundedRectangle(topLeadingRadius: 1, bottomLeadingRadius: 1,
                                           bottomTrailingRadius: 3, topTrailingRadius: 3)
                        .fill(notebookStyle.chip).frame(width: 8, height: 11)
                        .accessibilityHidden(true)
                }
                Text([provenance, notebookTitle].compactMap { $0 }.joined(separator: " · "))
                    .lineLimit(1)
            }
            .monoFont(11, style: .caption2).foregroundStyle(pal.faint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 16)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// A plain page row (group, A to Z, recent).
struct PageListRow: View {
    @Environment(\.palette) private var pal
    var page: KBPage
    var detail: String?

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(page.title).displayFont(19, style: .body).foregroundStyle(pal.ink)
                    .lineLimit(2).multilineTextAlignment(.leading)
                if let summary = page.summary, !summary.isEmpty {
                    Text(summary).uiFont(13, style: .footnote).foregroundStyle(pal.dim)
                        .lineLimit(2).multilineTextAlignment(.leading)
                }
                if let detail {
                    Text(detail).monoFont(11, style: .caption2).foregroundStyle(pal.faint)
                }
                if let verdict = page.verdict {
                    Text(verdict).monoFont(11, style: .caption2).foregroundStyle(pal.accent)
                }
            }
            Spacer(minLength: 0)
            IconView(icon: .forward, size: 16, lineWidth: 2).foregroundStyle(pal.chev)
        }
        .padding(.vertical, 12).frame(minHeight: 58)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct RowDivider: View {
    @Environment(\.palette) private var pal
    var body: some View { Rectangle().fill(pal.line2).frame(height: 1) }
}

/// Top bar used by the notebook-like screens: back + trailing buttons.
struct ScreenBar<Trailing: View>: View {
    var tint: Color
    @Environment(\.dismiss) private var dismiss
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 0) {
            Button { dismiss() } label: {
                IconView(icon: .back, size: 22, lineWidth: 2).foregroundStyle(tint)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .accessibilityLabel("Back")
            Spacer()
            trailing
        }
        .frame(minHeight: 44)
        .padding(.horizontal, 12)
    }
}

struct BarButton: View {
    var tint: Color
    var label: String
    var content: AnyView
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            content.foregroundStyle(tint).frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .accessibilityLabel(label)
    }
}

// MARK: - Notebook

/// The notebook's landing page: a text title block, search, the author's
/// Overview, what the last pull brought in, where the reader left off,
/// then the Contents (categories) and the other ways to browse.
struct NotebookView: View {
    @EnvironmentObject var store: KBStore
    @Environment(\.palette) private var pal
    var cacheName: String
    var onAppearance: () -> Void
    var onOpen: (Route) -> Void
    @State private var query = ""
    @State private var showAllGroups = false
    @State private var showFullDescription = false

    private static let groupPreview = 8

    private var kb: KnowledgeBase? { store.loaded[cacheName] }
    private var entry: LibraryKB? { store.library.kbs.first(where: { $0.cacheName == cacheName }) }
    private var style: CoverStyle { CoverStyle.forID(store.coverKey(forCacheName: cacheName)) }
    private var syncing: Bool { store.syncing.contains(cacheName) }

    var body: some View {
        VStack(spacing: 0) {
            ScreenBar(tint: pal.ink) {
                if let entry {
                    BarButton(tint: pal.ink, label: "Pull this notebook",
                              content: AnyView(IconView(icon: .refresh, size: 20, lineWidth: 1.75)
                                .rotationEffect(.degrees(syncing ? 360 : 0))
                                .animation(syncing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default,
                                           value: syncing))) {
                        Task { await store.pull(entry) }
                    }
                }
                BarButton(tint: pal.ink, label: "Notebook appearance",
                          content: AnyView(Text("Aa").displayFont(20, weight: .regular)),
                          action: onAppearance)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if let kb {
                        let groups = kb.browseGroups
                        header(kb, groups: groups)
                        SearchField(text: $query, prompt: "Search \(kb.pages.count) pages")
                            .padding(.top, 16)
                        if query.trimmingCharacters(in: .whitespaces).isEmpty {
                            landing(kb, groups: groups)
                        } else {
                            results(kb)
                        }
                    } else {
                        emptyState
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 60)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(pal.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: Header

    private func header(_ kb: KnowledgeBase, groups: [KnowledgeBase.BrowseGroup]) -> some View {
        let categories = groups.filter { $0.kind == .category }.count
        return VStack(alignment: .leading, spacing: 0) {
            Text(eyebrow(kb).uppercased()).monoFont(10, style: .caption2).tracking(1.2)
                .foregroundStyle(pal.accent).padding(.top, 14)
            Text(kb.manifest.shortTitle).displayFont(38, style: .largeTitle)
                .foregroundStyle(pal.ink).lineSpacing(-4)
                .padding(.top, 10).accessibilityAddTraits(.isHeader)
            if !kb.manifest.description.isEmpty {
                Text(kb.manifest.description).uiFont(13, style: .footnote)
                    .foregroundStyle(pal.dim).lineSpacing(3)
                    .lineLimit(showFullDescription ? nil : 2)
                    .padding(.top, 10)
                    .contentShape(Rectangle())
                    .onTapGesture { showFullDescription.toggle() }
                    .accessibilityHint(showFullDescription ? "" : "Double tap to read it all")
            }
            HStack(spacing: 14) {
                stat(kb.pages.count, "pages")
                if categories > 0 { stat(categories, categories == 1 ? "category" : "categories") }
                if let license = kb.manifest.license, !license.isEmpty {
                    Text(license).foregroundStyle(pal.dim).lineLimit(1)
                }
                Spacer(minLength: 0)
                Text(syncText)
                    .foregroundStyle(store.failures[cacheName] != nil ? pal.warn : pal.dim)
            }
            .uiFont(13, style: .footnote).foregroundStyle(pal.ink)
            .padding(.top, 18).padding(.bottom, 16)
            Rectangle().fill(pal.line).frame(height: 1)
        }
    }

    private func stat(_ count: Int, _ noun: String) -> Text {
        Text("\(count)").fontWeight(.semibold) + Text(" \(noun)")
    }

    private func eyebrow(_ kb: KnowledgeBase) -> String {
        let m = kb.manifest
        let parts = [m.profile, m.version].compactMap { $0 }.filter { !$0.isEmpty }
        return (parts + ["@ \(shortSHA(entry?.headSHA))"]).joined(separator: " · ")
    }

    private var syncText: String {
        if syncing { return "syncing…" }
        if store.failures[cacheName] != nil { return "stale" }
        if entry?.headSHA == nil { return "not pulled yet" }
        return "up to date"
    }

    // MARK: Landing

    @ViewBuilder
    private func landing(_ kb: KnowledgeBase, groups: [KnowledgeBase.BrowseGroup]) -> some View {
        let added = (entry?.addedSlugs ?? []).compactMap { kb.page(slug: $0) }
        let last = (entry?.recentSlugs ?? []).lazy.compactMap { kb.page(slug: $0) }.first

        if let overview = kb.overviewPage {
            NavigationLink(value: Route.page(cacheName, overview.slug)) {
                LandingRow(icon: .book, title: "Overview", detail: "The author's front page")
            }
            .buttonStyle(.plain).padding(.top, 12)
        }
        if !added.isEmpty {
            NavigationLink(value: Route.list(cacheName, PageListView.Kind.new.rawValue)) {
                LandingRow(label: added.count == 1 ? "1 page added by your last pull"
                                                   : "\(added.count) pages added by your last pull",
                           labelColor: pal.fresh,
                           title: added.map(\.title).joined(separator: ", "),
                           border: pal.accentLine)
            }
            .buttonStyle(.plain).padding(.top, 8)
        }
        if let last {
            NavigationLink(value: Route.page(cacheName, last.slug)) {
                LandingRow(icon: .bookmark, label: "Pick up where you left off", title: last.title)
            }
            .buttonStyle(.plain).padding(.top, 8)
        }

        if !groups.isEmpty {
            Text("Contents").displayFont(24, style: .title2).foregroundStyle(pal.ink)
                .padding(.top, 28).padding(.bottom, 6).accessibilityAddTraits(.isHeader)
            let addedSet = Set(added.map(\.slug))
            let shown = showAllGroups ? groups : Array(groups.prefix(Self.groupPreview))
            ForEach(shown, id: \.id) { group in
                let fresh = group.pages.filter { addedSet.contains($0.slug) }.count
                NavigationLink(value: Route.group(cacheName, group.id)) {
                    ContentsRow(title: group.title, count: group.pages.count, fresh: fresh)
                }
                .buttonStyle(.plain)
            }
            if groups.count > Self.groupPreview {
                Button { withAnimation { showAllGroups.toggle() } } label: {
                    Text(showAllGroups ? "Show fewer" : "All \(groups.count) categories")
                        .uiFont(14, style: .subheadline).foregroundStyle(pal.accent)
                        .frame(minHeight: 46).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }

        HStack(spacing: 8) {
            NavigationLink(value: Route.list(cacheName, PageListView.Kind.az.rawValue)) {
                BrowseTile(title: "A to Z", detail: "Every page")
            }
            NavigationLink(value: Route.list(cacheName, PageListView.Kind.recent.rawValue)) {
                BrowseTile(title: "Recent", detail: "Last updated")
            }
            Button {
                if let page = kb.listedPages.randomElement() {
                    onOpen(.page(cacheName, page.slug))
                }
            } label: {
                BrowseTile(title: "Random", detail: "Surprise me")
            }
            .accessibilityLabel("Open a random page")
        }
        .buttonStyle(.plain).padding(.top, 20)

        if let log = kb.logPage {
            NavigationLink(value: Route.page(cacheName, log.slug)) {
                if let latest = kb.latestLogEntry {
                    LandingRow(label: "Latest in the log · \(latest.date)", title: latest.title)
                } else {
                    LandingRow(title: "Log", detail: "What changed, and when")
                }
            }
            .buttonStyle(.plain).padding(.top, 8)
        }
    }

    @ViewBuilder
    private func results(_ kb: KnowledgeBase) -> some View {
        let hits = ComposedKB(name: kb.id, members: [kb]).search(query)
        if hits.isEmpty {
            Text("No pages match “\(query)”.").uiFont(15, style: .callout)
                .foregroundStyle(pal.dim).padding(.top, 24)
        } else {
            ForEach(Array(hits.enumerated()), id: \.element.route) { i, hit in
                let slug = String(hit.route.dropFirst("kb/\(kb.id)/".count))
                NavigationLink(value: Route.page(cacheName, slug)) {
                    SearchResultRow(title: hit.title, summary: hit.summary,
                                    provenance: hit.category, notebookStyle: style,
                                    notebookTitle: nil, query: query)
                }
                .buttonStyle(.plain)
                if i < hits.count - 1 { RowDivider() }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("Not pulled yet").displayFont(24, style: .title2).foregroundStyle(pal.ink)
            Text("Pull to clone this repository into the local cache.")
                .uiFont(15, style: .callout).foregroundStyle(pal.dim).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.top, 60)
    }
}

/// A full-width card row on the landing page: optional icon, a small
/// uppercase label or a detail line, and a display-face title.
private struct LandingRow: View {
    @Environment(\.palette) private var pal
    var icon: Icon?
    var label: String?
    var labelColor: Color?
    var title: String
    var detail: String?
    var border: Color?

    var body: some View {
        HStack(spacing: 12) {
            if let icon {
                IconView(icon: icon, size: 21, lineWidth: 1.9).foregroundStyle(pal.accent)
            }
            VStack(alignment: .leading, spacing: 3) {
                if let label {
                    Text(label.uppercased()).uiFont(11, weight: labelColor == nil ? .regular : .semibold,
                                                    style: .caption2)
                        .tracking(1.1).foregroundStyle(labelColor ?? pal.faint)
                }
                Text(title).displayFont(label == nil ? 19 : 17, style: .body)
                    .foregroundStyle(pal.ink).lineLimit(1)
                if let detail {
                    Text(detail).uiFont(12, style: .caption).foregroundStyle(pal.dim)
                }
            }
            Spacer(minLength: 0)
            IconView(icon: .forward, size: 16, lineWidth: 2).foregroundStyle(pal.chev)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .card(radius: 16, border: border)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// One line of the Contents: title, dotted leader, page count.
private struct ContentsRow: View {
    @Environment(\.palette) private var pal
    var title: String
    var count: Int
    var fresh: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).displayFont(18, style: .body).foregroundStyle(pal.ink)
                .multilineTextAlignment(.leading).layoutPriority(1)
            if fresh > 0 {
                Text("\(fresh) new").monoFont(10, style: .caption2).foregroundStyle(pal.fresh)
                    .fixedSize()
            }
            DottedLeader().stroke(pal.line3, style: StrokeStyle(lineWidth: 1.5, lineCap: .round,
                                                                dash: [0.1, 5]))
                .frame(minWidth: 16, maxWidth: .infinity).frame(height: 2)
                .accessibilityHidden(true)
            Text("\(count)").monoFont(12, style: .caption).foregroundStyle(pal.faint).fixedSize()
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(count) pages" + (fresh > 0 ? ", \(fresh) new" : ""))
    }
}

private struct DottedLeader: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

private struct BrowseTile: View {
    @Environment(\.palette) private var pal
    var title: String
    var detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).displayFont(17, style: .body).foregroundStyle(pal.ink).lineLimit(1)
            Text(detail).uiFont(12, style: .caption).foregroundStyle(pal.dim).lineLimit(1)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .card(radius: 14)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - A to Z / recently updated / new pages

struct PageListView: View {
    enum Kind: String { case az, recent, new }

    @EnvironmentObject var store: KBStore
    @Environment(\.palette) private var pal
    var cacheName: String
    var kind: Kind

    private var title: String {
        switch kind {
        case .az: return "A to Z"
        case .recent: return "Recently updated"
        case .new: return "New pages"
        }
    }

    var body: some View {
        let kb = store.loaded[cacheName]
        let pages: [KBPage] = {
            guard let kb else { return [] }
            switch kind {
            case .az: return kb.pagesAtoZ
            case .recent: return kb.pagesByRecency
            case .new:
                let slugs = store.library.kbs.first(where: { $0.cacheName == cacheName })?.addedSlugs ?? []
                return slugs.compactMap { kb.page(slug: $0) }
            }
        }()
        VStack(spacing: 0) {
            ScreenBar(tint: pal.ink) { }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    Text(kb?.title.uppercased() ?? "").monoFont(10, style: .caption2).tracking(1.2)
                        .foregroundStyle(pal.faint)
                    Text(title).displayFont(34, style: .largeTitle)
                        .foregroundStyle(pal.ink).padding(.top, 6)
                        .accessibilityAddTraits(.isHeader)
                    Text(kind == .new ? "Added by your last pull" : "\(pages.count) pages")
                        .uiFont(13, style: .footnote)
                        .foregroundStyle(pal.dim).padding(.top, 6).padding(.bottom, 8)
                    ForEach(Array(pages.enumerated()), id: \.element.slug) { i, page in
                        NavigationLink(value: Route.page(cacheName, page.slug)) {
                            PageListRow(page: page,
                                        detail: kind == .az ? nil
                                            : kind == .recent ? page.updated.map { "updated \($0)" }
                                            : page.category)
                        }
                        .buttonStyle(.plain)
                        if i < pages.count - 1 { RowDivider() }
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 60)
            }
        }
        .background(pal.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }
}

// MARK: - Category / type page list

struct GroupView: View {
    @EnvironmentObject var store: KBStore
    @Environment(\.palette) private var pal
    var cacheName: String
    var groupID: String

    var body: some View {
        let kb = store.loaded[cacheName]
        let group = kb?.browseGroup(id: groupID)
        VStack(spacing: 0) {
            ScreenBar(tint: pal.ink) { }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    Text(kb?.title.uppercased() ?? "").monoFont(10, style: .caption2).tracking(1.2)
                        .foregroundStyle(pal.faint)
                    Text(group?.title ?? "Not found").displayFont(34, style: .largeTitle)
                        .foregroundStyle(pal.ink).padding(.top, 6)
                        .accessibilityAddTraits(.isHeader)
                    Text("\(group?.pages.count ?? 0) pages").uiFont(13, style: .footnote)
                        .foregroundStyle(pal.dim).padding(.top, 6).padding(.bottom, 8)
                    if let pages = group?.pages {
                        ForEach(Array(pages.enumerated()), id: \.element.slug) { i, page in
                            NavigationLink(value: Route.page(cacheName, page.slug)) {
                                PageListRow(page: page, detail: nil)
                            }
                            .buttonStyle(.plain)
                            if i < pages.count - 1 { RowDivider() }
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 60)
            }
        }
        .background(pal.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }
}
