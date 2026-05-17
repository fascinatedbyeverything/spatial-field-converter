import SwiftUI

/// Top bar of Compose mode. Drives composition (re-)generation and the
/// Preview / Render+Upload actions.
public struct WorldDraftPane: View {
    @Binding public var title: String
    @Binding public var templateID: String
    @Binding public var durationSec: Double
    @Binding public var seed: UInt64

    public let isComposing: Bool
    public let isPreviewing: Bool
    public let isRendering: Bool
    public let canCompose: Bool      // false when set has zero kept elements
    public let canPreview: Bool      // false until there's a composition
    public let onCompose: () -> Void
    public let onReroll: () -> Void
    public let onPreviewToggle: () -> Void
    public let onRenderAndUpload: () -> Void

    public init(title: Binding<String>,
                templateID: Binding<String>,
                durationSec: Binding<Double>,
                seed: Binding<UInt64>,
                isComposing: Bool,
                isPreviewing: Bool,
                isRendering: Bool,
                canCompose: Bool,
                canPreview: Bool,
                onCompose: @escaping () -> Void,
                onReroll: @escaping () -> Void,
                onPreviewToggle: @escaping () -> Void,
                onRenderAndUpload: @escaping () -> Void) {
        self._title = title
        self._templateID = templateID
        self._durationSec = durationSec
        self._seed = seed
        self.isComposing = isComposing
        self.isPreviewing = isPreviewing
        self.isRendering = isRendering
        self.canCompose = canCompose
        self.canPreview = canPreview
        self.onCompose = onCompose
        self.onReroll = onReroll
        self.onPreviewToggle = onPreviewToggle
        self.onRenderAndUpload = onRenderAndUpload
    }

    public var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                TextField("World title", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 220)
                Text("seed \(seed)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Template").font(.caption2).foregroundStyle(.secondary)
                Picker("", selection: $templateID) {
                    ForEach(TemplateRegistry.all, id: \.id) { tpl in
                        Text(tpl.displayName).tag(tpl.id)
                    }
                }
                .labelsHidden()
                .frame(width: 160)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Duration").font(.caption2).foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    TextField("", value: $durationSec, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 64)
                    Text("s").font(.caption).foregroundStyle(.secondary)
                }
            }

            Button(action: onCompose) {
                if isComposing { ProgressView().controlSize(.mini) } else { Text("Compose") }
            }
            .disabled(!canCompose || isComposing)

            Button("Re-roll", action: onReroll)
                .disabled(!canCompose || isComposing)

            Spacer()

            Button(action: onPreviewToggle) {
                Label(isPreviewing ? "Stop" : "Preview",
                      systemImage: isPreviewing ? "stop.fill" : "play.fill")
            }
            .disabled(!canPreview || isRendering)

            Button(action: onRenderAndUpload) {
                if isRendering { ProgressView().controlSize(.mini) } else { Text("Render + Upload") }
            }
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(!canPreview || isRendering || title.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }
}
