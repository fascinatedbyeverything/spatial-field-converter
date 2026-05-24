import SwiftUI

public struct ContentView: View {

    @StateObject private var pipeline: ConversionPipeline = {
        let stagingRoot = PreferencesStore.stagingDirectory
        return ConversionPipeline(stagingDirectory: stagingRoot)
    }()

    @EnvironmentObject private var libraryIndex: R2CatalogIndex

    public enum Mode: String { case convert, library, compose }

    // Default to Convert — the H8 / VRH-8 ingest drop target is the primary
    // workflow. Library + Compose are downstream and reachable via the
    // segmented picker at the top of the window.
    @State private var mode: Mode = .convert

    // MARK: - Compose-mode state
    // Lazy-init via @State closures so first launch isn't slowed for Convert-only users.

    @State private var activeSet: SetData = SetData(
        name: "Untitled Set",
        slug: "untitled-set",
        createdAt: Date(),
        updatedAt: Date(),
        sources: [],
        elements: [])

    @State private var setStore: SetStore = {
        do { return try SetStore() }
        catch { fatalError("SetStore init: \(error)") }
    }()

    @State private var composePreviewPlayer: ComposePreviewPlayer = {
        let cache = PreferencesStore.stagingDirectory
            .appendingPathComponent("compose-cache", isDirectory: true)
        do { return try ComposePreviewPlayer(cacheDirectory: cache) }
        catch { fatalError("ComposePreviewPlayer init: \(error)") }
    }()

    private var composeCacheDirectory: URL {
        PreferencesStore.stagingDirectory
            .appendingPathComponent("compose-render", isDirectory: true)
    }

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Mode switcher — centered, fixed width, label hidden so the
            // segmented control renders reliably under the title bar.
            HStack {
                Spacer()
                Picker("Mode", selection: $mode) {
                    Text("Convert").tag(Mode.convert)
                    Text("Library").tag(Mode.library)
                    Text("Compose").tag(Mode.compose)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 360)
                Spacer()
            }
            .padding(.top, 10)
            .padding(.bottom, 8)

            Divider()

            switch mode {
            case .convert:
                convertView
            case .library:
                LibraryView(activeSet: $activeSet, setStore: setStore)
            case .compose:
                ComposeView(
                    set: $activeSet,
                    store: setStore,
                    previewPlayer: composePreviewPlayer,
                    renderCacheDirectory: composeCacheDirectory)
            }
        }
        .frame(minWidth: 1100, minHeight: 620)
        .onAppear {
            // Auto-switch to Convert when jobs are queued.
            if !pipeline.jobs.isEmpty { mode = .convert }
        }
        .onChange(of: pipeline.jobs.count) { count in
            if count > 0 && mode == .library { mode = .convert }
        }
    }

    @ViewBuilder
    private var convertView: some View {
        if pipeline.jobs.isEmpty {
            DropTargetView { urls in
                pipeline.addFiles(urls)
            }
            .padding()
        } else {
            HStack(spacing: 0) {
                InspectorView(pipeline: pipeline)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                VStack {
                    DropTargetView { urls in
                        pipeline.addFiles(urls)
                    }
                    .frame(width: 240, height: 240)
                    .padding()
                    Spacer()
                }
            }
        }
    }
}
