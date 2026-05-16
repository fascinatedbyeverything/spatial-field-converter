import Foundation

enum TempDirectory {
    static func makeUnique() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("spatial-field-converter-tests")
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
