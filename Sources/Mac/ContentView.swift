import SwiftUI

public struct ContentView: View {

    @StateObject private var pipeline: ConversionPipeline = {
        let stagingRoot = PreferencesStore.stagingDirectory
        let uploader = CloudUploaderBridge(uploaderExecutableURL: PreferencesStore.cloudUploaderExecutableURL)
        return ConversionPipeline(stagingDirectory: stagingRoot, uploader: uploader)
    }()

    public init() {}

    public var body: some View {
        Group {
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
        .frame(minWidth: 800, minHeight: 480)
    }
}
