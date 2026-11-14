import SwiftUI
import ReaderCore

/// The library home (Main.dc.html / A-Empty / A-Error): eyebrow + title,
/// failure cards, Continue reading, the notebook shelf, composed cards.
struct LibraryHome: View {
    @EnvironmentObject var store: KBStore
    @Environment(\.palette) private var pal
    var onAdd: () -> Void
    var onCompose: () -> Void
    var onSearch: () -> Void
    var onAppearance: () -> Void
    var onUpdateToken: (String) -> Void
    @State private var pendingRemoval: LibraryKB?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                Text("Library")
                    .displayFont(44, style: .largeTitle)
                    .tracking(-0.4)
                    .foregroundStyle(pal.ink)
                    .padding(.top, 10)
                    .accessibilityAddTraits(.isHeader)

                if store.library.kbs.isEmpty {
                    EmptyShelf(onAdd: onAdd)
                } else {
                    failureCards
                    continueCard
                    notebooks
                    composed
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
        .background(pal.bg.ignoresSafeArea())
        .refreshable { await store.pullAll() }
        .overlay(alignment: .bottom) {
            LibraryPill(onSearch: onSearch, onAppearance: onAppearance)
                .padding(.bottom, 14)
        }
        .confirmationDialog(
            "Remove \(pendingRemoval.map { store.loaded[$0.cacheName]?.title ?? $0.cacheName } ?? "notebook")?",
            isPresented: Binding(get: { pendingRemoval != nil },
                                 set: { if !$0 { pendingRemoval = nil } }),
            titleVisibility: .visible
        ) {
            Button("Remove from library", role: .destructive) {
                if let entry = pendingRemoval { store.removeKB(entry.cacheName) }
                pendingRemoval = nil
            }
        } message: {
            Text("Deletes the copy on this phone. The repository itself is untouched.")
        }
    }

    // MARK: Pieces

    private var header: some View {
        HStack {
            Text("OPENSHELF")
                .monoFont(11, style: .caption).tracking(2)
                .foregroundStyle(pal.accent)
            Spacer()
            if !store.library.kbs.isEmpty {
                HStack(spacing: 8) {
                    RoundIconButton(icon: .refresh, label: "Pull all notebooks",
                                    spinning: !store.syncing.isEmpty) {
                        Task { await store.pullAll() }
                    }
                    RoundIconButton(icon: .plus, label: "Add a knowledge base", filled: true,
                                    action: onAdd)
                }
            }
        }
        .frame(minHeight: 44)
    }

    private var failureCards: some View {
        ForEach(store.library.kbs.compactMap { store.failures[$0.cacheName] }
            .filter { !$0.dismissed }) { failure in
            FailureCard(failure: failure,
                        title: store.loaded[failure.cacheName]?.title ?? failure.cacheName,
                        sha: store.library.kbs.first(where: { $0.cacheName == failure.cacheName })?.headSHA,
                        onUpdateToken: { onUpdateToken(failure.cacheName) },
                        onRetry: {
                            if let e = store.library.kbs.first(where: { $0.cacheName == failure.cacheName }) {
                                Task { await store.pull(e) }
                            }
                        },
                        onDismiss: { store.dismissFailure(failure.cacheName) })
                .padding(.top, 22)
        }
    }

    @ViewBuilder
    private var continueCard: some View {
        if let target = store.continueReading {
            NavigationLink(value: target.route) {
                HStack(spacing: 14) {
                    MiniCover(style: CoverStyle.forID(target.coverKey), width: 44, height: 60, spine: 5)
                        .shadow(color: pal.shadow, radius: 7, y: 6)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("CONTINUE READING").uiFont(11, style: .caption2).tracking(1.1)
                            .foregroundStyle(pal.faint)
                        Text(target.title).displayFont(21, style: .title3)
                            .foregroundStyle(pal.ink).lineLimit(2)
                        Text(target.subtitle).uiFont(13, style: .footnote)
                            .foregroundStyle(pal.dim).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    IconView(icon: .forward, size: 20, lineWidth: 2).foregroundStyle(pal.accent)
                }
                .padding(14)
                .card()
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 22)
            .accessibilityLabel("Continue reading \(target.title), \(target.subtitle)")
        }
    }

    private var notebooks: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel(text: "Notebooks")
                Spacer()
                statusCaption
            }
            .padding(.top, 28)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(store.library.kbs, id: \.cacheName) { entry in
                        NavigationLink(value: Route.notebook(entry.cacheName)) {
                            cover(for: entry)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button { Task { await store.pull(entry) } } label: {
                                Label("Pull", systemImage: "arrow.clockwise")
                            }
                            Button(role: .destructive) { pendingRemoval = entry } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                    }
                    Button(action: onAdd) { AddCover() }.buttonStyle(.plain)
                        .accessibilityLabel("Add from Git")
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 24)
            }
            .padding(.horizontal, -20)
        }
    }

    private func cover(for entry: LibraryKB) -> some View {
        let kb = store.loaded[entry.cacheName]
        return ShelfCover(
            style: CoverStyle.forID(store.coverKey(forCacheName: entry.cacheName)),
            eyebrow: coverEyebrow(kb?.manifest),
            title: kb?.title ?? entry.cacheName,
            pageCount: kb?.pages.count,
            sha: entry.headSHA,
            syncing: store.syncing.contains(entry.cacheName),
            syncFraction: store.syncProgress[entry.cacheName] ?? 0,
            failed: store.failures[entry.cacheName] != nil)
    }

    private var statusCaption: some View {
        let failing = store.library.kbs.filter { store.failures[$0.cacheName] != nil }.count
        let text: String
        var color = pal.faint
        if failing > 0 { text = "\(failing) needs attention"; color = pal.warn }
        else if !store.syncing.isEmpty { text = "syncing…" }
        else if store.library.kbs.contains(where: { $0.headSHA == nil }) { text = "not pulled yet" }
        else { text = "all up to date" }
        return Text(text).monoFont(11, style: .caption).foregroundStyle(color)
    }

    @ViewBuilder
    private var composed: some View {
        HStack(alignment: .firstTextBaseline) {
            SectionLabel(text: "Composed")
            Spacer()
            Button(action: onCompose) {
                Text("New").uiFont(13, style: .footnote).foregroundStyle(pal.accent)
                    .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("New composition")
        }
        .padding(.top, 0)
        ForEach(store.library.compositions, id: \.name) { comp in
            NavigationLink(value: Route.composition(comp.name)) {
                HStack(spacing: 16) {
                    StackedCovers(back: coverStyle(comp, index: 1), front: coverStyle(comp, index: 0))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(comp.name).displayFont(20, style: .title3)
                            .foregroundStyle(pal.ink).lineLimit(2)
                        Text(memberLine(comp) + ", read as one corpus")
                            .uiFont(13, style: .footnote).foregroundStyle(pal.dim)
                            .lineSpacing(2)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
                .card()
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 12)
            .contextMenu {
                Button(role: .destructive) { store.removeComposition(comp.name) } label: {
                    Label("Delete composition", systemImage: "trash")
                }
            }
        }
        if store.library.compositions.isEmpty {
            Text("Read several notebooks as one corpus.")
                .uiFont(13, style: .footnote).foregroundStyle(pal.faint)
                .padding(.top, 4)
        }
    }

    private func coverStyle(_ comp: LibraryComposition, index: Int) -> CoverStyle {
        let names = comp.memberCacheNames
        let name = names.indices.contains(index) ? names[index] : names.first ?? comp.name
        return CoverStyle.forID(store.coverKey(forCacheName: name))
    }

    private func memberLine(_ comp: LibraryComposition) -> String {
        comp.memberCacheNames.map { store.loaded[$0]?.title ?? $0 }.joined(separator: " + ")
    }
}

// MARK: - Failure card

struct FailureCard: View {
    @Environment(\.palette) private var pal
    var failure: SyncFailure
    var title: String
    var sha: String?
    var onUpdateToken: () -> Void
    var onRetry: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                IconView(icon: .warn, size: 16, lineWidth: 2)
                Text("PULL FAILED").uiFont(11, weight: .semibold, style: .caption2).tracking(1.1)
            }
            .foregroundStyle(pal.warn)
            Text(failure.headline).displayFont(21, style: .title3)
                .foregroundStyle(pal.ink).lineSpacing(1)
            (Text("\(title) could not be updated. ")
             + (sha.map { Text("You can keep reading the copy on this phone, pinned at ")
                + Text(String($0.prefix(7))).font(.system(size: 12, design: .monospaced))
                + Text(".") } ?? Text("It has not been downloaded yet.")))
                .uiFont(14, style: .subheadline).foregroundStyle(pal.dim).lineSpacing(2)
            FlowLayout(spacing: 8) {
                if failure.kind == .auth {
                    Button(action: onUpdateToken) {
                        Text("Update token").uiFont(14, weight: .semibold, style: .subheadline)
                            .foregroundStyle(pal.bg).padding(.horizontal, 18).frame(minHeight: 44)
                            .background(Capsule().fill(pal.ink))
                    }
                }
                Button(action: onRetry) {
                    Text("Try again").uiFont(14, style: .subheadline).foregroundStyle(pal.ink)
                        .padding(.horizontal, 18).frame(minHeight: 44)
                        .overlay(Capsule().stroke(pal.line3, lineWidth: 1))
                }
                Button(action: onDismiss) {
                    Text("Dismiss").uiFont(14, style: .subheadline).foregroundStyle(pal.dim)
                        .padding(.horizontal, 12).frame(minHeight: 44)
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(border: pal.warnLine)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Empty library

struct EmptyShelf: View {
    @Environment(\.palette) private var pal
    var onAdd: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 10) {
                dashedBook(height: 128)
                dashedBook(height: 150)
                dashedBook(height: 136)
                    .rotationEffect(.degrees(8), anchor: .bottomLeading)
                    .padding(.leading, 4)
            }
            .padding(.top, 96)
            .accessibilityHidden(true)
            RoundedRectangle(cornerRadius: 2).fill(pal.line3).frame(height: 3)
                .padding(.horizontal, 24).accessibilityHidden(true)
            Text("Your shelf is empty")
                .displayFont(28, style: .title)
                .foregroundStyle(pal.ink).multilineTextAlignment(.center)
                .padding(.top, 40)
                .accessibilityAddTraits(.isHeader)
            Text("Add a Git repository that has a kb.yaml. It is cloned to this phone and kept in sync by pulling.")
                .uiFont(15, style: .callout).foregroundStyle(pal.dim)
                .multilineTextAlignment(.center).lineSpacing(3)
                .padding(.horizontal, 20).padding(.top, 12)
            Button(action: onAdd) {
                HStack(spacing: 8) {
                    IconView(icon: .plus, size: 20, lineWidth: 2.25)
                    Text("Add from Git").uiFont(16, weight: .semibold)
                }
                .foregroundStyle(pal.bg)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(Capsule().fill(pal.accent))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 34).padding(.top, 28)
        }
        .frame(maxWidth: .infinity)
    }

    private func dashedBook(height: CGFloat) -> some View {
        UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 4,
                               bottomTrailingRadius: 8, topTrailingRadius: 8)
            .stroke(pal.line3, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            .frame(width: 58, height: height)
    }
}
