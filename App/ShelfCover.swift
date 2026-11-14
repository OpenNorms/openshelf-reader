import SwiftUI
import ReaderCore

/// A notebook as a book cover (158 x 216): profile/version, title, page
/// count and short SHA; a syncing cover shows progress, a failed one a
/// warning badge and "stale".
struct ShelfCover: View {
    var style: CoverStyle
    var eyebrow: String
    var title: String
    var pageCount: Int?
    var sha: String?
    var syncing = false
    var syncFraction: Double = 0
    var failed = false

    static let size = CGSize(width: 158, height: 216)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(eyebrow.uppercased())
                .monoFont(10, style: .caption2).tracking(1.2)
                .foregroundStyle(style.sub).lineLimit(2)
                .padding(.trailing, failed ? 28 : 0)
            Text(title)
                .displayFont(25, style: .title2)
                .foregroundStyle(CoverStyle.text)
                .lineSpacing(-2).lineLimit(4).minimumScaleFactor(0.7)
                .padding(.top, 12)
            Spacer(minLength: 8)
            VStack(alignment: .leading, spacing: 3) {
                if syncing {
                    Text(syncFraction > 0 ? "Syncing \(Int(syncFraction * 100))%" : "Syncing…")
                        .uiFont(13, weight: .medium, style: .footnote)
                    ProgressBar(fraction: syncFraction, track: style.spine, fill: CoverStyle.text)
                        .frame(height: 3).padding(.vertical, 3)
                } else if let pageCount {
                    Text("\(pageCount) pages").uiFont(13, weight: .medium, style: .footnote)
                } else {
                    Text("Not pulled yet").uiFont(13, weight: .medium, style: .footnote)
                }
                Text(footer).monoFont(11, style: .caption2).foregroundStyle(style.sub)
            }
            .foregroundStyle(CoverStyle.text)
        }
        .padding(EdgeInsets(top: 16, leading: 24, bottom: 14, trailing: 14))
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .background(cover)
        .overlay(alignment: .topTrailing) {
            if failed {
                IconView(icon: .warn, size: 16, lineWidth: 2.2)
                    .foregroundStyle(Color(hex: 0xa8371f))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(CoverStyle.text))
                    .padding(10)
                    .accessibilityHidden(false)
                    .accessibilityLabel("Pull failed")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var footer: String {
        var s = sha.map { "@ \($0.prefix(7))" } ?? "unpinned"
        if failed { s += " · stale" }
        return s
    }

    private var accessibilityText: String {
        var parts = [title, eyebrow]
        if let pageCount { parts.append("\(pageCount) pages") }
        if failed { parts.append("pull failed, showing a stale copy") }
        if syncing { parts.append("syncing") }
        return parts.joined(separator: ", ")
    }

    private var cover: some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 5, bottomLeadingRadius: 5,
                                           bottomTrailingRadius: 12, topTrailingRadius: 12)
        return shape.fill(style.cover)
            .overlay(alignment: .leading) {
                HStack(spacing: 0) {
                    Rectangle().fill(style.spine).frame(width: 9)
                    Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1)
                }
            }
            .clipShape(shape)
            .shadow(color: .black.opacity(0.35), radius: 12, x: 0, y: 10)
    }
}

struct ProgressBar: View {
    var fraction: Double
    var track: Color
    var fill: Color
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(fill).frame(width: max(3, geo.size.width * min(max(fraction, 0), 1)))
            }
        }
        .accessibilityHidden(true)
    }
}

/// The dashed "Add from Git" cover at the end of the row.
struct AddCover: View {
    @Environment(\.palette) private var pal
    var body: some View {
        Text("Add from Git")
            .uiFont(13, style: .footnote)
            .foregroundStyle(pal.dim)
            .frame(width: ShelfCover.size.width, height: ShelfCover.size.height)
            .overlay(
                UnevenRoundedRectangle(topLeadingRadius: 5, bottomLeadingRadius: 5,
                                       bottomTrailingRadius: 12, topTrailingRadius: 12)
                    .stroke(pal.line3, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
            .contentShape(Rectangle())
    }
}

/// Eyebrow text for a notebook: "PROFILE · VERSION".
func coverEyebrow(_ manifest: KBManifest?) -> String {
    guard let manifest else { return "Knowledge base" }
    let parts = [manifest.profile, manifest.version].compactMap { $0 }.filter { !$0.isEmpty }
    if !parts.isEmpty { return parts.joined(separator: " · ") }
    if let spec = manifest.specVersion { return "OpenShelf \(spec)" }
    return "Knowledge base"
}

/// Left-to-right layout that wraps to new lines (alert card buttons).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(subviews, width: proposal.width ?? .infinity).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(subviews, width: bounds.width)
        for (i, f) in result.frames.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + f.minX, y: bounds.minY + f.minY),
                              proposal: ProposedViewSize(f.size))
        }
    }
    private func arrange(_ subviews: Subviews, width: CGFloat) -> (size: CGSize, frames: [CGRect]) {
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxW: CGFloat = 0
        var frames: [CGRect] = []
        for sub in subviews {
            let s = sub.sizeThatFits(.unspecified)
            if x > 0, x + s.width > width { x = 0; y += rowH + spacing; rowH = 0 }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: s))
            x += s.width + spacing; rowH = max(rowH, s.height); maxW = max(maxW, x - spacing)
        }
        return (CGSize(width: maxW, height: y + rowH), frames)
    }
}
