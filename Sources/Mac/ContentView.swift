import SwiftUI

public struct ContentView: View {

    @StateObject private var pipeline: ConversionPipeline = {
        let stagingRoot = PreferencesStore.stagingDirectory
        return ConversionPipeline(stagingDirectory: stagingRoot)
    }()

    @EnvironmentObject private var libraryIndex: R2CatalogIndex

    public enum Mode: String { case convert, library }

    // Default to Library if there are no queued jobs, Convert otherwise.
    @State private var mode: Mode = .library

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Mode switcher
            Picker("", selection: $mode) {
                Text("Convert").tag(Mode.convert)
                Text("Library").tag(Mode.library)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 240)
            .padding(.horizontal)
            .padding(.top, 10)
            .padding(.bottom, 8)

            Divider()

            switch mode {
            case .convert:
                convertView
            case .library:
                LibraryView()
            }
        }
        .frame(minWidth: 900, minHeight: 540)
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
