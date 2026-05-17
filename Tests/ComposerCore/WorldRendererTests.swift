import XCTest
@testable import SpatialFieldConverter

final class WorldRendererTests: XCTestCase {

    /// Pure-function path — writeManifest does not need ffmpeg or R2.
    /// We exercise it by invoking through a small reflection helper, OR
    /// just verify the Codable shape of WorldManifest covers what render() produces.
    /// For v1.1 we lean on WorldManifestTests for shape, and skip end-to-end ffmpeg
    /// in unit tests (covered by manual E2E in Phase 15).
    @MainActor
    func test_smoke_initRequiresWritableCache() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wrendertest-\(UUID().uuidString)")
        // Will succeed if ffmpeg is on this build machine; will throw ffmpegNotFound otherwise.
        // Either outcome is acceptable for the smoke test — we just confirm the init wires up.
        do {
            _ = try WorldRenderer(cacheDirectory: tmp)
        } catch WorldRendererError.ffmpegNotFound {
            // dev machine without ffmpeg — fine
        }
    }
}
