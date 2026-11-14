import SwiftUI
import ReaderCore

/// A-AddKB: stays open while the KB is cloned, shows the real steps and
/// any failure, and dismisses itself on success.
struct AddKBSheet: View {
    @EnvironmentObject var store: KBStore
    @Environment(\.palette) private var pal
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var branch = ""
    @State private var token = ""

    private var running: Bool { store.addProgress?.isRunning ?? false }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") { dismiss() }
                    .uiFont(15, style: .callout).foregroundStyle(pal.dim)
                    .frame(minHeight: 44).disabled(running)
                Spacer()
            }
            .padding(.horizontal, 20).padding(.top, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .bottom, spacing: 16) {
                        MiniCover(style: CoverStyle.palette[0], width: 60, height: 82, spine: 6)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Add to your library").displayFont(28, style: .title)
                                .foregroundStyle(pal.ink).lineSpacing(-2)
                                .accessibilityAddTraits(.isHeader)
                            Text("Any Git repo with a kb.yaml. Cloned to this phone, never written to.")
                                .uiFont(13, style: .footnote).foregroundStyle(pal.dim)
                        }
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        field("Git URL", note: nil) {
                            DesignField(placeholder: "https://github.com/…", text: $url, keyboard: .URL)
                        }
                        field("Branch", note: "optional") {
                            DesignField(placeholder: "default branch", text: $branch)
                        }
                        field("Access token", note: "private repos only") {
                            DesignField(placeholder: "not needed for public repos", text: $token, secure: true)
                        }
                    }
                    .disabled(running)
                    .padding(.top, 20)

                    if let progress = store.addProgress {
                        FieldLabel(text: "Progress").padding(.top, 20)
                        ProgressCard(progress: progress).padding(.top, 8)
                        if let error = progress.error {
                            Text(error)
                                .uiFont(14, style: .subheadline).foregroundStyle(pal.warn)
                                .padding(.top, 10).accessibilityLabel("Error. \(error)")
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
            }
            .scrollDismissesKeyboard(.interactively)

            PrimaryButton(title: running ? "Adding to library…" : "Add to library",
                          enabled: !running && !url.trimmingCharacters(in: .whitespaces).isEmpty) {
                let u = url, b = branch, t = token
                Task {
                    let ok = await store.addKB(remoteURL: u, branch: b.isEmpty ? nil : b,
                                               token: t.isEmpty ? nil : t)
                    if ok { dismiss() }
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 24).padding(.top, 8)
        }
        .interactiveDismissDisabled(running)
        .onDisappear { store.resetAdd() }
        .sheetChrome()
    }

    private func field<C: View>(_ label: String, note: String?, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            FieldLabel(text: label, note: note)
            content()
        }
    }
}

private struct ProgressCard: View {
    @Environment(\.palette) private var pal
    var progress: AddProgress

    private enum State { case pending, active, done, failed }

    private func state(_ phase: AddProgress.Phase) -> State {
        if progress.phase == .done || progress.phase.rawValue > phase.rawValue { return .done }
        if progress.phase == phase { return progress.error != nil ? .failed : .active }
        return .pending
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            row("clone", state(.cloning),
                value: state(.cloning) == .done ? "done"
                    : (state(.cloning) == .active && progress.cloneFraction > 0
                       ? "\(Int(progress.cloneFraction * 100))%" : nil))
            row("read kb.yaml", state(.readingManifest),
                value: progress.specVersion.map { "openshelf \($0)" })
            row("index pages", state(.indexing), value: progress.pageCount.map(String.init))
            ProgressBar(fraction: progress.error == nil ? progress.fraction : progress.fraction,
                        track: pal.line, fill: progress.error == nil ? pal.accent : pal.warn)
                .frame(height: 3)
                .animation(.easeOut(duration: 0.25), value: progress.fraction)
        }
        .monoFont(13, style: .footnote)
        .foregroundStyle(pal.ink)
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(pal.bg))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(pal.line, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private func row(_ title: String, _ state: State, value: String?) -> some View {
        HStack(spacing: 10) {
            Group {
                switch state {
                case .done: IconView(icon: .check, size: 16, lineWidth: 2.4).foregroundStyle(pal.accent)
                case .failed: IconView(icon: .warn, size: 16, lineWidth: 2).foregroundStyle(pal.warn)
                case .active: Spinner()
                case .pending: Circle().stroke(pal.line3, lineWidth: 2).frame(width: 14, height: 14)
                }
            }
            .frame(width: 16, height: 16)
            Text(title).frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(state == .pending ? pal.faint : pal.ink)
            if let value { Text(value).foregroundStyle(pal.dim) }
        }
    }
}

private struct Spinner: View {
    @Environment(\.palette) private var pal
    @State private var spin = false
    var body: some View {
        Circle().trim(from: 0, to: 0.75)
            .stroke(pal.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .frame(width: 14, height: 14)
            .rotationEffect(.degrees(spin ? 360 : 0))
            .animation(.linear(duration: 0.9).repeatForever(autoreverses: false), value: spin)
            .onAppear { spin = true }
    }
}
