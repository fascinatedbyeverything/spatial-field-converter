import XCTest
import AVFoundation
@testable import SpatialFieldConverter

@MainActor
final class ComposePreviewPlayerTests: XCTestCase {

    private func makeTempCache() -> URL {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ComposePreviewPlayerTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        return tmp
    }

    func test_init_succeedsAndExposesNotPlaying() throws {
        let p = try ComposePreviewPlayer(cacheDirectory: makeTempCache())
        XCTAssertFalse(p.isPlaying)
        XCTAssertNil(p.currentSlug)
    }

    func test_stop_isIdempotentBeforeStart() throws {
        let p = try ComposePreviewPlayer(cacheDirectory: makeTempCache())
        p.stop()
        p.stop()
        XCTAssertFalse(p.isPlaying)
    }

    func test_updateObjectPosition_outOfRange_isNoop() throws {
        let p = try ComposePreviewPlayer(cacheDirectory: makeTempCache())
        // No objects loaded yet — must not crash
        p.updateObjectPosition(index: 0, x: 1, y: 0, z: 0)
        p.updateObjectPosition(index: 99, x: 1, y: 0, z: 0)
    }
}
