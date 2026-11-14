import SwiftUI
import ReaderCore

/// The chrome colour tokens of the "Stacks" design, for both modes.
/// Resolved from the colour scheme; views read `@Environment(\.palette)`
/// instead of using default List/Form styling.
struct AppPalette: Equatable {
    var bg: Color
    var panel: Color
    var nav: Color
    var line: Color
    var line2: Color
    var line3: Color
    var ink: Color
    var dim: Color
    var faint: Color
    var accent: Color
    var accentLine: Color
    var chev: Color
    var warn: Color
    var warnLine: Color
    var scrim: Color
    var markBG: Color
    var markInk: Color
    var shadow: Color
    /// "New" markers (pages a pull brought in).
    var fresh: Color

    static let dark = AppPalette(
        bg: Color(hex: 0x0b0e13), panel: Color(hex: 0x131821),
        nav: Color(hex: 0x1a202b).opacity(0.94),
        line: Color(hex: 0x262e3a), line2: Color(hex: 0x1c232e), line3: Color(hex: 0x323b49),
        ink: Color(hex: 0xece6d9), dim: Color(hex: 0xa3acb7), faint: Color(hex: 0x8f99a7),
        accent: Color(hex: 0xe8a33d), accentLine: Color(hex: 0x6b4d1e), chev: Color(hex: 0x5d6877),
        warn: Color(hex: 0xf0806a), warnLine: Color(hex: 0x7a3327),
        scrim: Color(hex: 0x05070a),
        markBG: Color(hex: 0xe8a33d).opacity(0.22), markInk: Color(hex: 0xf6d9a6),
        shadow: Color.black.opacity(0.5), fresh: Color(hex: 0x2dd4bf))

    static let light = AppPalette(
        bg: Color(hex: 0xf6f2e8), panel: Color(hex: 0xfffdf7),
        nav: Color(hex: 0xfffdf7).opacity(0.96),
        line: Color(hex: 0xddd5c2), line2: Color(hex: 0xe6dfcf), line3: Color(hex: 0xcfc6b0),
        ink: Color(hex: 0x1c1a16), dim: Color(hex: 0x5c564a), faint: Color(hex: 0x6b6457),
        accent: Color(hex: 0x9a5a0c), accentLine: Color(hex: 0xd9b98a), chev: Color(hex: 0xa39a86),
        warn: Color(hex: 0xa8371f), warnLine: Color(hex: 0xe0b3a8),
        scrim: Color(hex: 0xb9b1a0),
        markBG: Color(hex: 0x9a5a0c).opacity(0.16), markInk: Color(hex: 0x6f3f05),
        shadow: Color(hex: 0x463414).opacity(0.2), fresh: Color(hex: 0x1d7566))

    static func resolve(_ scheme: ColorScheme) -> AppPalette {
        scheme == .dark ? .dark : .light
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xff) / 255,
                  green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255)
    }
}

extension EnvironmentValues {
    /// Derived from the colour scheme, so it follows Mode changes everywhere
    /// (sheets included) without being passed around.
    var palette: AppPalette { AppPalette.resolve(colorScheme) }
}

private struct TypefaceKey: EnvironmentKey { static let defaultValue = Typeface.serif }
extension EnvironmentValues {
    var typeface: Typeface {
        get { self[TypefaceKey.self] }
        set { self[TypefaceKey.self] = newValue }
    }
}

// MARK: - Fonts

/// Sizes follow the design in points at the default Dynamic Type size and
/// scale with it (relative to `style`).
private struct ScaledFont: ViewModifier {
    @ScaledMetric var size: CGFloat
    var weight: Font.Weight
    var design: Font.Design?
    var useTypeface: Bool
    @Environment(\.typeface) private var typeface

    init(size: CGFloat, weight: Font.Weight, design: Font.Design?,
         useTypeface: Bool, style: Font.TextStyle) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: style)
        self.weight = weight
        self.design = design
        self.useTypeface = useTypeface
    }

    func body(content: Content) -> some View {
        let resolved: Font.Design = useTypeface
            ? (typeface == .serif ? .serif : .default)
            : (design ?? .default)
        content.font(.system(size: size, weight: weight, design: resolved))
    }
}

extension View {
    /// Display text (titles, cover titles, row titles): follows the Typeface setting.
    func displayFont(_ size: CGFloat, weight: Font.Weight = .medium,
                     style: Font.TextStyle = .body) -> some View {
        modifier(ScaledFont(size: size, weight: weight, design: nil, useTypeface: true, style: style))
    }
    /// Chrome text: always the system sans.
    func uiFont(_ size: CGFloat, weight: Font.Weight = .regular,
                style: Font.TextStyle = .body) -> some View {
        modifier(ScaledFont(size: size, weight: weight, design: .default, useTypeface: false, style: style))
    }
    /// Mono labels (eyebrows, SHAs, counts).
    func monoFont(_ size: CGFloat, weight: Font.Weight = .regular,
                  style: Font.TextStyle = .caption) -> some View {
        modifier(ScaledFont(size: size, weight: weight, design: .monospaced, useTypeface: false, style: style))
    }
}

// MARK: - Cover colours

/// One deep cover colour: the board, its darker spine, and the lighter
/// text tone for secondary lines. `chip` is the small search-result tag.
struct CoverStyle: Equatable {
    var cover: Color
    var spine: Color
    var sub: Color
    var chip: Color

    static let text = Color(hex: 0xf1ecdf)

    static let palette: [CoverStyle] = [
        CoverStyle(cover: Color(hex: 0x14463f), spine: Color(hex: 0x0e332e), sub: Color(hex: 0xa8d5c9), chip: Color(hex: 0x1f6b60)),
        CoverStyle(cover: Color(hex: 0x542420), spine: Color(hex: 0x3d1916), sub: Color(hex: 0xe6bdb6), chip: Color(hex: 0x8a3a32)),
        CoverStyle(cover: Color(hex: 0x1d3257), spine: Color(hex: 0x132240), sub: Color(hex: 0xb6c6e4), chip: Color(hex: 0x3a5a94)),
        CoverStyle(cover: Color(hex: 0x45264e), spine: Color(hex: 0x311a38), sub: Color(hex: 0xd8bfe2), chip: Color(hex: 0x7a4a8a)),
        CoverStyle(cover: Color(hex: 0x3e4a1c), spine: Color(hex: 0x2c3514), sub: Color(hex: 0xcdd6a4), chip: Color(hex: 0x6b7a2e)),
        CoverStyle(cover: Color(hex: 0x4b3523), spine: Color(hex: 0x36251a), sub: Color(hex: 0xdcc7b0), chip: Color(hex: 0x8a6a48)),
    ]

    /// Deterministic: the same KB id always gets the same colour.
    static func forID(_ id: String) -> CoverStyle {
        palette[coverPaletteIndex(for: id, paletteSize: palette.count)]
    }
}
