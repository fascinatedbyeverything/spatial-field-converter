import XCTest
@testable import SpatialFieldConverter

final class CloudUploaderBridgeTests: XCTestCase {
    var tempDir: URL!

    override func setUp() { super.setUp(); tempDir = TempDirectory.makeUnique() }
    override func tearDown() { TempDirectory.cleanup(tempDir); super.tearDown() }

    func test_invokesUploaderWithCorrectArguments() async throws {
        // Mock uploader: a shell script that records its argv to a file and exits 0
        let mockUploader = tempDir.appendingPathComponent("mock-uploader")
        let recordFile = tempDir.appendingPathComponent("argv-record.txt")
        let script = """
        #!/bin/bash
        printf '%s\\n' "$@" > "\(recordFile.path)"
        echo "uploaded: stems/spatial-mix/field-recording/test-slug/"
        exit 0
        """
        try script.write(to: mockUploader, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: mockUploader.path)

        let bridge = CloudUploaderBridge(uploaderExecutableURL: mockUploader)
        let admURL = tempDir.appendingPathComponent("master.wav")
        try Data().write(to: admURL)   // touch the file so it exists

        let result = try await bridge.uploadADMBWF(
            admBwfURL: admURL,
            programmeName: "Forest morning",
            category: "field-recording"
        )

        let recorded = try String(contentsOf: recordFile)
        let lines = recorded.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.first, "--process-adm-bwf", "first arg should be --process-adm-bwf flag")
        XCTAssertEqual(lines[safe: 1], admURL.path, "second arg should be the file path")
        XCTAssertTrue(recorded.contains("--category"))
        XCTAssertTrue(recorded.contains("field-recording"))
        XCTAssertTrue(recorded.contains("--name"))
        XCTAssertTrue(recorded.contains("Forest morning"))

        XCTAssertTrue(result.r2Key.contains("stems/spatial-mix/field-recording/test-slug/"),
                      "result should expose the R2 key reported by uploader")
    }

    func test_throwsOnNonzeroExit() async throws {
        let mockUploader = tempDir.appendingPathComponent("mock-uploader-fail")
        let script = """
        #!/bin/bash
        echo "ERROR: simulated failure" >&2
        exit 7
        """
        try script.write(to: mockUploader, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: mockUploader.path)

        let bridge = CloudUploaderBridge(uploaderExecutableURL: mockUploader)
        let admURL = tempDir.appendingPathComponent("master.wav")
        try Data().write(to: admURL)

        do {
            _ = try await bridge.uploadADMBWF(admBwfURL: admURL, programmeName: "x", category: "field-recording")
            XCTFail("expected throw")
        } catch CloudUploaderBridgeError.uploaderExitedNonZero(let code, let stderr) {
            XCTAssertEqual(code, 7)
            XCTAssertTrue(stderr.contains("simulated failure"))
        }
    }

    func test_throwsWhenUploaderExecutableMissing() async throws {
        let missing = tempDir.appendingPathComponent("does-not-exist")
        let bridge = CloudUploaderBridge(uploaderExecutableURL: missing)
        let admURL = tempDir.appendingPathComponent("master.wav")
        try Data().write(to: admURL)

        do {
            _ = try await bridge.uploadADMBWF(admBwfURL: admURL, programmeName: "x", category: "")
            XCTFail("expected throw")
        } catch CloudUploaderBridgeError.uploaderNotFound {
            // expected
        }
    }
}

// Helper for safe array indexing in tests
private extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
