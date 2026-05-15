import XCTest
@testable import SpatialFieldConverter

final class AmbisonicWavWriterTests: XCTestCase {
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = TempDirectory.makeUnique()
    }

    override func tearDown() {
        TempDirectory.cleanup(tempDir)
        super.tearDown()
    }

    func test_writes4Channel24Bit48kHzWavWithIxmlChunk() throws {
        let url = tempDir.appendingPathComponent("source.wav")
        let writer = try AmbisonicWavWriter(url: url, sampleRate: 48000, bitsPerSample: 24)
        let frames = 1000
        var buffer = [Float](repeating: 0, count: frames * 4)
        for f in 0..<frames {
            buffer[f * 4 + 0] = 0.5     // W
        }
        try writer.appendFrames(buffer, frameCount: frames)
        try writer.finalize()

        let reader = try WavFileReader(url: url)
        XCTAssertEqual(reader.metadata.channelCount, 4)
        XCTAssertEqual(reader.metadata.sampleRate, 48000)
        XCTAssertEqual(reader.metadata.bitsPerSample, 24)
        XCTAssertEqual(reader.metadata.frameCount, frames)
        XCTAssertNotNil(reader.metadata.ixmlContent)
        XCTAssertTrue(reader.metadata.ixmlContent?.contains("AmbiX") == true)
        XCTAssertTrue(reader.metadata.ixmlContent?.contains("ACN") == true)
        XCTAssertTrue(reader.metadata.ixmlContent?.contains("SN3D") == true)
    }
}
