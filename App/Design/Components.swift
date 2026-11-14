import SwiftUI
import ReaderCore

// MARK: - Small pieces

/// 13pt uppercase section label ("NOTEBOOKS").
struct SectionLabel: View {
    @Environment(\.palette) private var pal
    var text: String
    var body: some View {
        Text(text.uppercased())
            .uiFont(13, weight: .semibold, style: .footnote)
            .tracking(1.3)
            .foregroundStyle(pal.dim)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Tiny uppercase field label ("GIT URL").
struct FieldLabel: View {
    @Environment(\.palette) private var pal
    var text: String
    var note: String?
    var body: some View {
        (Text(text.uppercased()).tracking(1.1)
         + (note.map { Text("  · \($0)").tracking(0) } ?? Text("")))
            .uiFont(11, style: .caption)
            .foregroundStyle(pal.faint)
    }
}

/// 44pt round icon button (pull all, add, ...).
struct RoundIconButton: View {
    @Environment(\.palette) private var pal
    var icon: Icon
    var label: String
    var filled = false
    var spinning = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(filled ? pal.accent : pal.panel)
                Circle().stroke(filled ? .clear : pal.line, lineWidth: 1)
                IconView(icon: icon, size: 20, lineWidth: filled ? 2.25 : 1.75)
                    .foregroundStyle(filled ? pal.bg : pal.ink)
                    .rotationEffect(.degrees(spinning ? 360 : 0))
                    .animation(spinning
                               ? .linear(duration: 1).repeatForever(autoreverses: false)
                               : .default, value: spinning)
            }
            .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Pill-shaped toggle used for tabs and scope chips (min 44pt tall).
struct PillChip<Leading: View>: View {
    @Environment(\.palette) private var pal
    var title: String
    var selected: Bool
    @ViewBuilder var leading: Leading
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                leading
                Text(title).lineLimit(1)
            }
            .uiFont(14, weight: selected ? .semibold : .regular, style: .subheadline)
            .foregroundStyle(selected ? pal.bg : pal.dim)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .background(Capsule().fill(selected ? pal.ink : .clear))
            .overlay(Capsule().stroke(selected ? .clear : pal.line, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
extension PillChip where Leading == EmptyView {
    init(title: String, selected: Bool, action: @escaping () -> Void) {
        self.init(title: title, selected: selected, leading: { EmptyView() }, action: action)
    }
}

/// A radio group drawn as the design's segmented control (selected = `line`).
struct Segments<Value: Hashable>: View {
    @Environment(\.palette) private var pal
    var options: [(value: Value, title: String)]
    @Binding var selection: Value
    var font: ((Value) -> AnyView)?

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options.indices, id: \.self) { i in
                let opt = options[i]
                let on = opt.value == selection
                Button { selection = opt.value } label: {
                    Group {
                        if let font { font(opt.value) } else { Text(opt.title).uiFont(15, style: .callout) }
                    }
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .foregroundStyle(on ? pal.ink : pal.dim)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(RoundedRectangle(cornerRadius: 12).fill(on ? pal.line : .clear))
                    .contentShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(opt.title)
                .accessibilityAddTraits(on ? [.isSelected] : [])
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 16).fill(pal.bg))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(pal.line, lineWidth: 1))
    }
}

struct PrimaryButton: View {
    @Environment(\.palette) private var pal
    var title: String
    var enabled = true
    /// The outlined, muted look of a disabled call to action.
    var outlinedWhenDisabled = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .uiFont(16, weight: .semibold)
                .lineLimit(2).multilineTextAlignment(.center)
                .foregroundStyle(enabled ? pal.bg : (outlinedWhenDisabled ? pal.faint : pal.bg))
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(Capsule().fill(enabled || !outlinedWhenDisabled ? pal.accent : .clear))
                .overlay(Capsule().stroke(!enabled && outlinedWhenDisabled ? pal.line3 : .clear, lineWidth: 1))
                .opacity(enabled || outlinedWhenDisabled ? 1 : 0.85)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

/// Spine-and-board mini book (continue card, compose members, chips).
struct MiniCover: View {
    var style: CoverStyle
    var width: CGFloat
    var height: CGFloat
    var spine: CGFloat = 4

    var body: some View {
        UnevenRoundedRectangle(topLeadingRadius: width * 0.08, bottomLeadingRadius: width * 0.08,
                               bottomTrailingRadius: width * 0.16, topTrailingRadius: width * 0.16)
            .fill(style.cover)
            .overlay(alignment: .leading) { Rectangle().fill(style.spine).frame(width: spine) }
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: width * 0.08, bottomLeadingRadius: width * 0.08,
                                              bottomTrailingRadius: width * 0.16, topTrailingRadius: width * 0.16))
            .frame(width: width, height: height)
            .accessibilityHidden(true)
    }
}

/// Two overlapping covers: a composition.
struct StackedCovers: View {
    var back: CoverStyle
    var front: CoverStyle
    var scale: CGFloat = 1

    var body: some View {
        ZStack(alignment: .topLeading) {
            MiniCover(style: back, width: 42 * scale, height: 58 * scale, spine: 4 * scale)
                .rotationEffect(.degrees(7), anchor: .bottomLeading)
                .offset(x: 14 * scale)
            MiniCover(style: front, width: 42 * scale, height: 58 * scale, spine: 4 * scale)
                .shadow(color: .black.opacity(0.35), radius: 5, x: 2, y: 1)
                .offset(y: 2 * scale)
        }
        .frame(width: 58 * scale, height: 62 * scale, alignment: .topLeading)
        .accessibilityHidden(true)
    }
}

/// Section / group card surface.
struct CardBackground: ViewModifier {
    @Environment(\.palette) private var pal
    var radius: CGFloat = 18
    var border: Color?
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: radius).fill(pal.panel))
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(border ?? pal.line, lineWidth: 1))
    }
}
extension View {
    func card(radius: CGFloat = 18, border: Color? = nil) -> some View {
        modifier(CardBackground(radius: radius, border: border))
    }
}

// MARK: - Floating bars

/// The floating pill at the bottom of the library: Library / Search / Aa.
struct LibraryPill: View {
    @Environment(\.palette) private var pal
    var onSearch: () -> Void
    var onAppearance: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            HStack(spacing: 8) {
                IconView(icon: .library, size: 20)
                Text("Library").uiFont(14, weight: .semibold, style: .subheadline)
            }
            .foregroundStyle(pal.bg)
            .padding(.horizontal, 18).frame(height: 48)
            .background(Capsule().fill(pal.accent))
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits([.isButton, .isSelected])
            .accessibilityLabel("Library")

            Button(action: onSearch) {
                IconView(icon: .search, size: 21)
                    .foregroundStyle(pal.ink).frame(width: 56, height: 48)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Search")
            Button(action: onAppearance) {
                Text("Aa").displayFont(20, weight: .regular)
                    .foregroundStyle(pal.ink).frame(width: 56, height: 48)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Appearance")
        }
        .buttonStyle(.plain)
        .floatingChrome()
    }
}

extension View {
    /// Rounded blurred bar with the design's border and drop shadow.
    func floatingChrome() -> some View { modifier(FloatingChrome()) }
}
private struct FloatingChrome: ViewModifier {
    @Environment(\.palette) private var pal
    func body(content: Content) -> some View {
        content
            .padding(6)
            .background(Capsule().fill(.ultraThinMaterial))
            .background(Capsule().fill(pal.nav))
            .overlay(Capsule().stroke(pal.line3, lineWidth: 1))
            .shadow(color: pal.shadow, radius: 16, x: 0, y: 16)
    }
}

/// Fade at the bottom edge, as in the design's scrolled screens.
struct BottomFade: View {
    @Environment(\.palette) private var pal
    var height: CGFloat = 90
    var body: some View {
        LinearGradient(colors: [pal.bg.opacity(0), pal.bg], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.7))
            .frame(height: height)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

// MARK: - Sheets

extension View {
    /// Panel-coloured sheet with the design's 28pt top corners.
    func sheetChrome(detents: Set<PresentationDetent> = [.large]) -> some View {
        modifier(SheetChrome(detents: detents))
    }
}
private struct SheetChrome: ViewModifier {
    @Environment(\.palette) private var pal
    var detents: Set<PresentationDetent>
    func body(content: Content) -> some View {
        content
            .background(pal.panel.ignoresSafeArea())
            .presentationDetents(detents)
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(28)
            .presentationBackground(pal.panel)
    }
}

/// Text field in the design's rounded, bordered style.
struct DesignField: View {
    @Environment(\.palette) private var pal
    var placeholder: String
    @Binding var text: String
    var secure = false
    var mono = true
    var keyboard: UIKeyboardType = .default

    var body: some View {
        Group {
            if secure { SecureField(placeholder, text: $text) }
            else { TextField(placeholder, text: $text) }
        }
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .keyboardType(keyboard)
        .modifier(FieldFont(mono: mono))
        .foregroundStyle(pal.ink)
        .padding(.horizontal, 14)
        .frame(minHeight: 50)
        .background(RoundedRectangle(cornerRadius: 14).fill(pal.bg))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(pal.line, lineWidth: 1))
    }
}
private struct FieldFont: ViewModifier {
    var mono: Bool
    func body(content: Content) -> some View {
        if mono { content.monoFont(13, style: .footnote) }
        else { content.displayFont(18, style: .body) }
    }
}

/// Highlights `query` inside `text` using the design's mark colours.
struct HighlightedText: View {
    @Environment(\.palette) private var pal
    var text: String
    var query: String

    var body: some View {
        Text(attributed)
    }

    private var attributed: AttributedString {
        var out = AttributedString()
        for seg in SearchHighlight.segments(text, query: query) {
            var part = AttributedString(seg.text)
            if seg.matched {
                part.backgroundColor = pal.markBG
                part.foregroundColor = pal.markInk
            }
            out += part
        }
        return out
    }
}

// MARK: - Back gesture

/// The screens hide the system navigation bar (they draw their own), which
/// also disables the edge-swipe back gesture; this restores it.
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    open override func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }
    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}
