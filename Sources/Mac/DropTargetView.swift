import SwiftUI
import UniformTypeIdentifiers

/// SwiftUI drop zone for .wav files and folders containing .wav files.
/// Recurses folders and collects all .wav files, sorted by path.
public struct DropTargetView: View {

    public var onDropFiles: ([URL]) -> Void
    @State private var isTargeted: Bool = false

    public init(onDropFiles: @escaping ([URL]) -> Void) {
        self.onDropFiles = onDropFiles
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.gray.opacity(0.4),
                    style: StrokeStyle(lineWidth: 2, dash: [8, 6])
                )
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(isTargeted ? Color.accentColor.opacity(0.1) : Color.gray.opacity(0.05))
                )
            VStack(spacing: 12) {
                Image(systemName: "waveform.circle")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                    .foregroundStyle(.secondary)
                Text("Drop a Zoom H8 .wav file or an SD card folder")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            Task {
                var urls: [URL] = []
                for provider in providers {
                    if let url = await Self.loadURL(from: provider) {
                        urls.append(contentsOf: Self.expandToWavFiles(url))
                    }
                }
                if !urls.isEmpty {
                    await MainActor.run {
                        onDropFiles(urls)
                    }
                }
            }
            return true
        }
    }

    private static func loadURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { (cont: CheckedContinuation<URL?, Never>) in
            _ = provider.loadObject(ofClass: URL.self) { obj, _ in
                cont.resume(returning: obj)
            }
        }
    }

    private static func expandToWavFiles(_ url: URL) -> [URL] {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return [] }
        if isDir.boolValue {
            let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil)
            var found: [URL] = []
            while let next = enumerator?.nextObject() as? URL {
                if next.pathExtension.lowercased() == "wav" {
                    found.append(next)
                }
            }
            return found.sorted { $0.path < $1.path }
        } else if url.pathExtension.lowercased() == "wav" {
            return [url]
        }
        return []
    }
}
