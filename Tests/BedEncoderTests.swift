import XCTest
import AVFoundation
@testable import SpatialFieldConverter

final class BedEncoderTests: XCTestCase {
    var tempDir: URL!

    override func setUp() { super.setUp(); tempDir = TempDirectory.makeUnique() }
    override func tearDown() { TempDirectory.cleanup(tempDir); super.tearDown() }

    func test_encodes7_1_2_AAC_m4a_thatPlaysViaAVFoundation() async throws {
        let url = tempDir.appendingPathComponent("bed.m4a")
        let encoder = try BedEncoder(outputURL: url, sampleRate: 48000)

        // 1 second of silence × 10 channels
        let frameCount = 48000
        let channels = 10
        let buffer = [Float](repeating: 0, count: frameCount * channels)
        try encoder.appendFrames(buffer, frameCount: frameCount)
        try await encoder.finalize()

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertEqual(tracks.count, 1)
        let formatDescriptions = try await tracks[0].load(.formatDescriptions)
        XCTAssertGreaterThan(formatDescriptions.count, 0)
        let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescriptions[0])
        XCTAssertEqual(asbd?.pointee.mChannelsPerFrame, 10)
        XCTAssertEqual(asbd?.pointee.mSampleRate, 48000)
    }
}
