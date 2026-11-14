import SwiftUI

/// The design's icons, drawn on its 24x24 grid so they stay crisp at any
/// size and need no assets. Stroke width and colour come from the caller.
enum Icon {
    case back, forward, plus, search, library, arrowLeft, arrowRight
    case outline, warn, check, refresh, book, bookmark, shuffle

    fileprivate func path(in r: CGRect) -> Path {
        let s = min(r.width, r.height) / 24
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: r.minX + x * s, y: r.minY + y * s)
        }
        var path = Path()
        func poly(_ pts: [(CGFloat, CGFloat)]) {
            path.move(to: p(pts[0].0, pts[0].1))
            for pt in pts.dropFirst() { path.addLine(to: p(pt.0, pt.1)) }
        }
        func arc(_ cx: CGFloat, _ cy: CGFloat, _ radius: CGFloat,
                 from a: CGFloat, to b: CGFloat) {
            let steps = 24
            for i in 0...steps {
                let t = (a + (b - a) * CGFloat(i) / CGFloat(steps)) * .pi / 180
                let pt = p(cx + radius * cos(t), cy + radius * sin(t))
                if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
            }
        }
        switch self {
        case .back: poly([(15, 5), (8, 12), (15, 19)])
        case .forward: poly([(9, 5), (16, 12), (9, 19)])
        case .plus:
            poly([(12, 5), (12, 19)]); poly([(5, 12), (19, 12)])
        case .search:
            path.addEllipse(in: CGRect(x: r.minX + 4.5 * s, y: r.minY + 4.5 * s,
                                       width: 13 * s, height: 13 * s))
            poly([(16, 16), (20.5, 20.5)])
        case .library:
            poly([(5, 4), (5, 20)]); poly([(10, 4), (10, 20)])
            poly([(14.5, 5.5), (19, 19.5)])
        case .arrowLeft:
            poly([(19, 12), (5, 12)]); poly([(11, 6), (5, 12), (11, 18)])
        case .arrowRight:
            poly([(5, 12), (19, 12)]); poly([(13, 6), (19, 12), (13, 18)])
        case .outline:
            poly([(5, 7), (19, 7)]); poly([(5, 12), (15, 12)]); poly([(5, 17), (11, 17)])
        case .warn:
            poly([(12, 4), (21, 20), (3, 20), (12, 4)])
            poly([(12, 10), (12, 15)]); poly([(12, 17.5), (12, 18)])
        case .check: poly([(5, 12.5), (9.5, 17), (19, 7.5)])
        case .book:
            poly([(12, 6), (9, 4.6), (4, 4), (4, 18), (9, 18.6), (12, 20),
                  (15, 18.6), (20, 18), (20, 4), (15, 4.6), (12, 6)])
            poly([(12, 6), (12, 20)])
        case .bookmark: poly([(7, 4), (17, 4), (17, 20), (12, 16), (7, 20), (7, 4)])
        case .shuffle:
            poly([(4, 7), (8, 7), (16, 17), (20, 17)])
            poly([(4, 17), (8, 17), (10.6, 13.8)])
            poly([(13.4, 10.2), (16, 7), (20, 7)])
            poly([(18, 4.5), (20.5, 7), (18, 9.5)])
            poly([(18, 14.5), (20.5, 17), (18, 19.5)])
        case .refresh:
            arc(12, 12, 8, from: -7, to: -140); path.addLine(to: p(4, 8))
            poly([(4, 4), (4, 8), (8, 8)])
            arc(12, 12, 8, from: 173, to: 40); path.addLine(to: p(20, 16))
            poly([(20, 20), (20, 16), (16, 16)])
        }
        return path
    }
}

struct IconView: View {
    var icon: Icon
    var size: CGFloat = 20
    var lineWidth: CGFloat = 1.9

    var body: some View {
        IconShape(icon: icon)
            .stroke(style: StrokeStyle(lineWidth: lineWidth * size / 24,
                                       lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

private struct IconShape: Shape {
    var icon: Icon
    func path(in rect: CGRect) -> Path { icon.path(in: rect) }
}
