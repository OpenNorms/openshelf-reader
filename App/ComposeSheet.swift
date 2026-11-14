import SwiftUI
import ReaderCore

/// A-Compose: name + at least two member notebooks.
struct ComposeSheet: View {
    @EnvironmentObject var store: KBStore
    @Environment(\.palette) private var pal
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var selected: Set<String> = []

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
    private var nameTaken: Bool {
        store.library.compositions.contains { $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame }
    }
    private var valid: Bool { selected.count >= 2 && !trimmedName.isEmpty && !nameTaken }

    /// Says what is missing until the form can be submitted.
    private var buttonTitle: String {
        if selected.count < 2 { return selected.isEmpty ? "Choose two to create" : "Choose one more to create" }
        if trimmedName.isEmpty { return "Name it to create" }
        if nameTaken { return "That name is already used" }
        return "Create composition"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") { dismiss() }
                    .uiFont(15, style: .callout).foregroundStyle(pal.dim).frame(minHeight: 44)
                Spacer()
            }
            .padding(.horizontal, 20).padding(.top, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .bottom, spacing: 18) {
                        StackedCovers(back: CoverStyle.palette[1], front: CoverStyle.palette[0], scale: 1.25)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("New composition").displayFont(28, style: .title).foregroundStyle(pal.ink)
                                .accessibilityAddTraits(.isHeader)
                            Text("Read several notebooks as one corpus.")
                                .uiFont(13, style: .footnote).foregroundStyle(pal.dim)
                        }
                    }
                    VStack(alignment: .leading, spacing: 7) {
                        FieldLabel(text: "Name")
                        DesignField(placeholder: "Composition name", text: $name, mono: false)
                    }
                    .padding(.top, 22)

                    HStack(alignment: .firstTextBaseline) {
                        FieldLabel(text: "Members")
                        Spacer()
                        Text("choose at least two").uiFont(12, style: .caption).foregroundStyle(pal.dim)
                    }
                    .padding(.top, 20)

                    VStack(spacing: 0) {
                        ForEach(Array(store.library.kbs.enumerated()), id: \.element.cacheName) { i, entry in
                            memberRow(entry)
                            if i < store.library.kbs.count - 1 {
                                Rectangle().fill(pal.line2).frame(height: 1)
                            }
                        }
                        if store.library.kbs.isEmpty {
                            Text("Add a notebook first.").uiFont(14, style: .subheadline)
                                .foregroundStyle(pal.dim).padding(.vertical, 20)
                        }
                    }
                    .padding(.horizontal, 14)
                    .background(RoundedRectangle(cornerRadius: 16).fill(pal.bg))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(pal.line, lineWidth: 1))
                    .padding(.top, 8)

                    Text("Browsing and search run across every member. Links between them resolve, and each page keeps its source notebook and commit.")
                        .uiFont(13, style: .footnote).foregroundStyle(pal.dim).lineSpacing(3)
                        .padding(.top, 16)
                }
                .padding(.horizontal, 20)
            }
            .scrollDismissesKeyboard(.interactively)

            PrimaryButton(title: buttonTitle, enabled: valid, outlinedWhenDisabled: true) {
                // Keep the library's order for members.
                let members = store.library.kbs.map(\.cacheName).filter(selected.contains)
                store.addComposition(name: trimmedName, memberCacheNames: members)
                dismiss()
            }
            .padding(.horizontal, 20).padding(.bottom, 24).padding(.top, 8)
        }
        .sheetChrome()
    }

    private func memberRow(_ entry: LibraryKB) -> some View {
        let kb = store.loaded[entry.cacheName]
        let on = selected.contains(entry.cacheName)
        return Button {
            if on { selected.remove(entry.cacheName) } else { selected.insert(entry.cacheName) }
        } label: {
            HStack(spacing: 14) {
                MiniCover(style: CoverStyle.forID(store.coverKey(forCacheName: entry.cacheName)),
                          width: 30, height: 42, spine: 3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(kb?.title ?? entry.cacheName).displayFont(18, style: .body)
                        .foregroundStyle(pal.ink).lineLimit(2)
                    Text("\(kb.map { "\($0.pages.count) pages" } ?? "not pulled") · @ \(shortSHA(entry.headSHA))")
                        .monoFont(11, style: .caption2).foregroundStyle(pal.faint)
                }
                Spacer(minLength: 8)
                ZStack {
                    RoundedRectangle(cornerRadius: 7).fill(on ? pal.accent : .clear)
                    RoundedRectangle(cornerRadius: 7).stroke(on ? .clear : pal.line3, lineWidth: 1.5)
                    if on { IconView(icon: .check, size: 16, lineWidth: 2.6).foregroundStyle(pal.bg) }
                }
                .frame(width: 24, height: 24)
            }
            .frame(minHeight: 68)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
    }
}

/// Token entry after a rejected pull (the failure card's Update token).
struct UpdateTokenSheet: View {
    @EnvironmentObject var store: KBStore
    @Environment(\.palette) private var pal
    @Environment(\.dismiss) private var dismiss
    var cacheName: String
    @State private var token = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button("Cancel") { dismiss() }
                    .uiFont(15, style: .callout).foregroundStyle(pal.dim).frame(minHeight: 44)
                Spacer()
            }
            Text("Update access token").displayFont(28, style: .title).foregroundStyle(pal.ink)
                .accessibilityAddTraits(.isHeader)
            Text("A new token for \(store.loaded[cacheName]?.title ?? cacheName). It is kept in the Keychain on this phone, and the pull is retried right away.")
                .uiFont(13, style: .footnote).foregroundStyle(pal.dim).lineSpacing(3)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 7) {
                FieldLabel(text: "Access token")
                DesignField(placeholder: "paste a personal access token", text: $token, secure: true)
            }
            .padding(.top, 20)
            Spacer(minLength: 16)
            PrimaryButton(title: "Save and try again",
                          enabled: !token.trimmingCharacters(in: .whitespaces).isEmpty) {
                let t = token
                dismiss()
                Task { await store.updateToken(t, for: cacheName) }
            }
        }
        .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 24)
        .sheetChrome(detents: [.height(380), .large])
    }
}
