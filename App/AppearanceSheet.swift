import SwiftUI
import ReaderCore

/// Who opened Appearance: a notebook (which allows "Only this one") or
/// the library / a composition (global only).
struct AppearanceContext: Identifiable {
    var cacheName: String?
    var id: String { cacheName ?? "global" }
}

/// A-Appearance: Mode, Typeface, Reading theme, Text size, Apply-to scope.
struct AppearanceSheet: View {
    @EnvironmentObject var store: KBStore
    @Environment(\.palette) private var pal
    @Environment(\.colorScheme) private var scheme
    var context: AppearanceContext
    @Environment(\.dismiss) private var dismiss

    private enum Scope: Hashable { case every, only }
    @State private var scope: Scope = .every
    @State private var size: Double = 17
    @State private var didSetup = false

    private var dark: Bool { scheme == .dark }
    private var override: String? {
        context.cacheName.flatMap { name in
            store.library.kbs.first(where: { $0.cacheName == name })?.themeName
        }
    }
    /// The theme the swatches mark as selected for the active scope.
    private var selectedTheme: String {
        if scope == .only, let override { return override }
        return store.library.readingTheme(dark: dark).name
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Appearance").displayFont(26, style: .title2).foregroundStyle(pal.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Done") { dismiss() }
                    .uiFont(15, weight: .semibold, style: .callout)
                    .foregroundStyle(pal.ink).frame(minWidth: 44, minHeight: 44)
            }
            .padding(.horizontal, 20).padding(.top, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    group("Mode") {
                        Segments(options: [(.system, "Match system"), (.light, "Light"), (.dark, "Dark")],
                                 selection: Binding(get: { store.library.appearanceMode },
                                                    set: { store.setMode($0) }))
                    }
                    group("Typeface") {
                        Segments(options: [(.serif, "Serif"), (.sans, "Sans")],
                                 selection: Binding(get: { store.library.typeface },
                                                    set: { store.setTypeface($0) }),
                                 font: { face in
                            AnyView(Text(face == .serif ? "Serif" : "Sans")
                                .font(.system(size: face == .serif ? 18 : 15,
                                              design: face == .serif ? .serif : .default)))
                        })
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline) {
                            FieldLabel(text: "Reading theme")
                            Spacer()
                            Text("remembered per mode").uiFont(12, style: .caption).foregroundStyle(pal.dim)
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(ReaderTheme.bundled, id: \.name) { theme in
                                    swatch(theme)
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                        .padding(.horizontal, -20)
                    }
                    group("Text size") {
                        HStack(spacing: 14) {
                            Text("A").displayFont(15, weight: .regular).foregroundStyle(pal.dim)
                                .accessibilityHidden(true)
                            Slider(value: $size, in: Double(ReaderTheme.minTextSize)...Double(ReaderTheme.maxTextSize),
                                   step: 1) { editing in
                                if !editing { store.setTextSize(Int(size)) }
                            }
                            .tint(pal.accent)
                            .frame(minHeight: 44)
                            .accessibilityLabel("Text size")
                            .accessibilityValue("\(Int(size)) points")
                            Text("A").displayFont(24, weight: .regular).foregroundStyle(pal.ink)
                                .accessibilityHidden(true)
                        }
                        .padding(.horizontal, 16).frame(minHeight: 52)
                        .background(RoundedRectangle(cornerRadius: 16).fill(pal.bg))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(pal.line, lineWidth: 1))
                    }
                    if context.cacheName != nil {
                        group("Apply reading theme to") {
                            Segments(options: [(.every, "Every notebook"), (.only, "Only this one")],
                                     selection: $scope)
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 24)
            }
        }
        .onAppear {
            guard !didSetup else { return }
            didSetup = true
            size = Double(store.library.textSize)
            scope = override != nil ? .only : .every
        }
        .sheetChrome(detents: [.height(652), .large])
    }

    private func group<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(text: title)
            content()
        }
    }

    private func swatch(_ theme: ReaderTheme) -> some View {
        let on = selectedTheme == theme.name
        let ink = Color(cssHex: theme.token("ink"))
        return Button {
            switch scope {
            case .every:
                store.setReadingTheme(theme.name, dark: dark)
                if let name = context.cacheName { store.setTheme(nil, for: name) }
            case .only:
                if let name = context.cacheName { store.setTheme(theme.name, for: name) }
            }
        } label: {
            VStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Aa").displayFont(20, weight: .regular).foregroundStyle(ink).lineLimit(1)
                    RoundedRectangle(cornerRadius: 2).fill(ink.opacity(0.7)).frame(height: 3)
                    RoundedRectangle(cornerRadius: 2).fill(Color(cssHex: theme.token("amber")))
                        .frame(width: 28, height: 3)
                }
                .padding(.horizontal, 10).padding(.vertical, 11)
                .frame(width: 76, height: 88, alignment: .topLeading)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(cssHex: theme.token("bg"))))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(on ? pal.accent : pal.line, lineWidth: 2))
                Text(theme.name).uiFont(13, weight: on ? .semibold : .regular, style: .footnote)
                    .foregroundStyle(on ? pal.accent : pal.dim)
            }
            .frame(width: 76)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(theme.name), \(theme.isDark ? "dark" : "light") theme")
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }
}

extension Color {
    /// A "#rrggbb" token from a reader theme.
    init(cssHex: String) {
        var s = cssHex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        self.init(hex: UInt32(s, radix: 16) ?? 0)
    }
}
