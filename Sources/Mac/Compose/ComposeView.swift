import SwiftUI

/// Compose mode root. Three-pane layout:
///   - LEFT: SetCurationPane (curate the Set this World draws from)
///   - CENTER: WorldDraftPane (top) + TimelineView + SpaceView (split)
///   - RIGHT: ObjectInspectorView
@MainActor
public struct ComposeView: View {
    @Binding public var set: SetData
    public let store: SetStore
    public let previewPlayer: ComposePreviewPlayer
    public let renderCacheDirectory: URL

    @State private var composition: Composition?
    @State private var title: String = "Untitled World"
    @State private var templateID: String = TemplateRegistry.all.first?.id ?? "greatest_hits"
    @State private var durationSec: Double = 300
    @State private var seed: UInt64 = 1
    @State private var selectedObjectIndex: Int? = nil

    @State private var isComposing = false
    @State private var isRendering = false
    @State private var statusMessage: String? = nil

    public init(set: Binding<SetData>,
                store: SetStore,
                previewPlayer: ComposePreviewPlayer,
                renderCacheDirectory: URL) {
        self._set = set
        self.store = store
        self.previewPlayer = previewPlayer
        self.renderCacheDirectory = renderCacheDirectory
    }

    public var body: some View {
        HStack(spacing: 0) {
            SetCurationPane(set: $set, store: store)
                .frame(minWidth: 320, idealWidth: 360, maxWidth: 420)
            Divider()
            VStack(spacing: 0) {
                WorldDraftPane(
                    title: $title,
                    templateID: $templateID,
                    durationSec: $durationSec,
                    seed: $seed,
                    isComposing: isComposing,
                    isPreviewing: previewPlayer.isPlaying,
                    isRendering: isRendering,
                    canCompose: !set.keptElements.isEmpty,
                    canPreview: composition != nil,
                    onCompose: { doCompose(reroll: false) },
                    onReroll: { doCompose(reroll: true) },
                    onPreviewToggle: { doPreviewToggle() },
                    onRenderAndUpload: { Task { await doRenderAndUpload() } })
                Divider()
                if composition != nil {
                    HSplitView {
                        VStack(spacing: 0) {
                            TimelineView(
                                composition: Binding(
                                    get: { composition! },
                                    set: { composition = $0 }),
                                selectedObjectIndex: $selectedObjectIndex)
                                .frame(minHeight: 220)
                            Divider()
                            SpaceView(
                                composition: Binding(
                                    get: { composition! },
                                    set: { composition = $0 }),
                                selectedObjectIndex: $selectedObjectIndex,
                                onPositionLiveDrag: { i, x, y, z in
                                    previewPlayer.updateObjectPosition(index: i, x: x, y: y, z: z)
                                })
                                .frame(minHeight: 220)
                        }
                        .frame(minWidth: 360)
                        ObjectInspectorView(
                            composition: Binding(
                                get: { composition! },
                                set: { composition = $0 }),
                            selectedObjectIndex: selectedObjectIndex)
                            .frame(minWidth: 260, maxWidth: 360)
                    }
                } else {
                    emptyState
                }
                if let msg = statusMessage {
                    Divider()
                    Text(msg).font(.caption).padding(.horizontal).padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Text("No composition yet").font(.headline).foregroundStyle(.secondary)
            Text("Curate the Set on the left, then click Compose.")
                .font(.caption).foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func doCompose(reroll: Bool) {
        guard !set.keptElements.isEmpty else { return }
        if reroll {
            seed = UInt64.random(in: 1...UInt64(UInt32.max))
        }
        isComposing = true
        statusMessage = "Composing..."
        do {
            let comp = try Composer.compose(
                set: set,
                templateID: templateID,
                durationSec: durationSec,
                seed: seed,
                title: title)
            composition = comp
            selectedObjectIndex = nil
            statusMessage = "Composed \(comp.objects.count) objects, bed of \(comp.bedPlan.segments.count) segments."
        } catch {
            statusMessage = "Compose failed: \(error)"
        }
        isComposing = false
    }

    private func doPreviewToggle() {
        if previewPlayer.isPlaying {
            previewPlayer.stop()
            return
        }
        guard let comp = composition else { return }
        Task {
            statusMessage = "Prefetching object clips for preview..."
            do {
                let pairs = try await previewPlayer.prefetchObjects(comp.objects)
                guard let firstSeg = comp.bedPlan.segments.first else {
                    statusMessage = "No bed segments to preview."
                    return
                }
                let bedURL = try await previewPlayer.prefetchBedSegment(r2Key: firstSeg.sourceClipR2Key)
                try previewPlayer.start(bedURL: bedURL,
                                        objects: pairs,
                                        slug: comp.slug ?? "preview")
                statusMessage = "Preview playing — make sure AirPods Spatial Audio is on."
            } catch {
                statusMessage = "Preview failed: \(error)"
            }
        }
    }

    private func doRenderAndUpload() async {
        guard let comp = composition else { return }
        isRendering = true
        statusMessage = "Rendering bundle..."
        do {
            let renderer = try WorldRenderer(cacheDirectory: renderCacheDirectory)
            let renderOut = renderCacheDirectory.appendingPathComponent("rendered", isDirectory: true)
            let rendered = try await renderer.render(comp, into: renderOut)
            statusMessage = "Uploading to R2..."
            let worldUploader = WorldUploader()
            let r2 = try await worldUploader.uploadRendered(rendered, title: title, durationSec: durationSec)
            statusMessage = "Uploaded: \(r2)"
        } catch {
            statusMessage = "Render+Upload failed: \(error)"
        }
        isRendering = false
    }
}
