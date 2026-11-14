import SwiftUI
import ReaderCore

/// Everything one rendered page needs, independent of where it came from.
struct PageContent {
    var pageID: String
    var title: String
    var summary: String?
    var chips: [String]
    var fragmentHTML: String
    var headings: [Markdown.OutlineItem]
    var provenance: String?
    var metadata: [(key: String, value: String)]
    /// Shown in the slim top bar (the page's category, else its notebook).
    var contextLabel: String
}

/// A-Reader: slim top bar, scroll-progress hairline, the page, and the
/// floating reading bar (previous, next, on this page, search, library).
struct PageReaderView: View {
    @Environment(\.palette) private var pal
    @Environment(\.dismiss) private var dismiss
    var content: PageContent
    var theme: ReaderTheme
    var typeface: Typeface
    var textSize: Int
    var fileURL: (_ kbID: String, _ path: String) -> URL?
    var onRoute: (String) -> Void
    var onSwipe: (ReaderWebView.SwipeDirection) -> Void = { _ in }
    var canGoForward = false
    var onForward: () -> Void
    var onSearch: () -> Void
    var onLibrary: () -> Void
    var onAppearance: () -> Void

    @State private var controller = ReaderWebController()
    @State private var showOutline = false

    private var document: String {
        theme.htmlDocument(
            title: content.title, bodyHTML: content.fragmentHTML,
            provenance: content.provenance, metadata: content.metadata,
            header: .init(title: content.title, summary: content.summary, chips: content.chips),
            typeface: typeface, textSize: textSize)
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ProgressHairline(progress: controller.progress)
            ReaderWebView(html: document, fileURL: fileURL, onRoute: onRoute, onSwipe: onSwipe,
                          canGoForward: canGoForward, controller: controller, pageID: content.pageID)
                .ignoresSafeArea(edges: .bottom)
        }
        .background(pal.bg.ignoresSafeArea())
        .overlay(alignment: .bottom) { readingBar.padding(.bottom, 14) }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showOutline) {
            OutlineSheet(headings: content.headings) { id in
                showOutline = false
                controller.scrollToHeading(id: id)
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 4) {
            Button { dismiss() } label: {
                IconView(icon: .back, size: 22, lineWidth: 2).foregroundStyle(pal.ink)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .accessibilityLabel("Back")
            Text(content.contextLabel).uiFont(13, style: .footnote).foregroundStyle(pal.dim)
                .lineLimit(1).frame(maxWidth: .infinity)
            Button(action: onAppearance) {
                Text("Aa").displayFont(20, weight: .regular).foregroundStyle(pal.ink)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .accessibilityLabel("Appearance")
        }
        .padding(.horizontal, 12)
    }

    private var readingBar: some View {
        HStack(spacing: 2) {
            barButton(.arrowLeft, "Previous page", enabled: true) { dismiss() }
            barButton(.arrowRight, "Next page", enabled: canGoForward, action: onForward)
            Rectangle().fill(pal.line3).frame(width: 1, height: 24).padding(.horizontal, 4)
                .accessibilityHidden(true)
            barButton(.outline, "On this page", enabled: !content.headings.isEmpty) { showOutline = true }
            barButton(.search, "Search", enabled: true, action: onSearch)
            barButton(.library, "Library", enabled: true, size: 20, action: onLibrary)
        }
        .floatingChrome()
    }

    private func barButton(_ icon: Icon, _ label: String, enabled: Bool, size: CGFloat = 21,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            IconView(icon: icon, size: size)
                .foregroundStyle(enabled ? pal.ink : pal.chev)
                .frame(width: 52, height: 48).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}

/// 2pt reading-progress line under the top bar.
private struct ProgressHairline: View {
    @Environment(\.palette) private var pal
    @ObservedObject var progress: ScrollProgress
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(pal.line2)
                Rectangle().fill(pal.accent).frame(width: geo.size.width * progress.fraction)
            }
        }
        .frame(height: 2)
        .accessibilityHidden(true)
    }
}

/// "On this page": the page's headings; tapping one scrolls to it.
private struct OutlineSheet: View {
    @Environment(\.palette) private var pal
    var headings: [Markdown.OutlineItem]
    var onPick: (String) -> Void

    var body: some View {
        let minLevel = headings.map(\.level).min() ?? 1
        VStack(alignment: .leading, spacing: 0) {
            Text("On this page").displayFont(26, style: .title2).foregroundStyle(pal.ink)
                .padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 8)
                .accessibilityAddTraits(.isHeader)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(headings.enumerated()), id: \.offset) { i, h in
                        Button { onPick(h.id) } label: {
                            Text(h.text)
                                .displayFont(h.level <= minLevel ? 19 : 16, style: .body)
                                .foregroundStyle(h.level <= minLevel ? pal.ink : pal.dim)
                                .multilineTextAlignment(.leading)
                                .padding(.leading, CGFloat(min(h.level - minLevel, 3)) * 16)
                                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if i < headings.count - 1 { RowDivider() }
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 30)
            }
        }
        .sheetChrome(detents: [.medium, .large])
    }
}
