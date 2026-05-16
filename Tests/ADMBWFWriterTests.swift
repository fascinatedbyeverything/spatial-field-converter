import XCTest
@testable import SpatialFieldConverter

final class ADMBWFWriterTests: XCTestCase {
    var tempDir: URL!

    override func setUp() { super.setUp(); tempDir = TempDirectory.makeUnique() }
    override func tearDown() { TempDirectory.cleanup(tempDir); super.tearDown() }

    func test_writes10Channel24Bit48kAdmBwfWithAxmlAndChna() throws {
        let url = tempDir.appendingPathComponent("master.wav")
        let session = ADMBedSession(programmeName: "Test Field Recording")
        let writer = try ADMBWFWriter(url: url, session: session)

        // 1 second of silence × 10 channels (interleaved L, R, C, LFE, Lss, Rss, Lrs, Rrs, Ltf, Rtf)
        let frameCount = 48000
        let cc = ADMBedConfig.channelCount
        let buffer = [Float](repeating: 0, count: frameCount * cc)
        try writer.appendBedFrames(buffer, frameCount: frameCount)
        try writer.finalize()

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        // Re-read with WavFileReader — confirm format + chunks
        let reader = try WavFileReader(url: url)
        let meta = reader.metadata
        XCTAssertEqual(meta.channelCount, 10)
        XCTAssertEqual(meta.sampleRate, 48000)
        XCTAssertEqual(meta.bitsPerSample, 24)
        XCTAssertEqual(meta.frameCount, frameCount)

        // axml chunk extraction — verify it contains the marker strings
        let raw = try Data(contentsOf: url)
        XCTAssertTrue(raw.contains("audioFormatExtended".data(using: .ascii)!), "axml must be present")
        XCTAssertTrue(raw.contains("AP_00010003".data(using: .ascii)!), "7.1.2 pack ID must be present")
        XCTAssertTrue(raw.contains("ATU_00000001".data(using: .ascii)!), "track UID 1 must be present")
        XCTAssertTrue(raw.contains("ATU_00000010".data(using: .ascii)!), "track UID 10 must be present")
        XCTAssertTrue(raw.contains("Test Field Recording".data(using: .ascii)!), "programme name must be present")

        // chna chunk: locate "chna" magic, parse header
        guard let chnaRange = raw.range(of: "chna".data(using: .ascii)!) else {
            XCTFail("chna chunk not found")
            return
        }
        let chnaStart = chnaRange.lowerBound
        // 4 bytes id + 4 bytes size + 4 bytes (numTracks + numUIDs)
        let chnaSize = raw.subdata(in: chnaStart + 4..<chnaStart + 8)
            .withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        let numTracks = raw.subdata(in: chnaStart + 8..<chnaStart + 10)
            .withUnsafeBytes { $0.load(as: UInt16.self).littleEndian }
        let numUIDs = raw.subdata(in: chnaStart + 10..<chnaStart + 12)
            .withUnsafeBytes { $0.load(as: UInt16.self).littleEndian }
        XCTAssertEqual(numTracks, 10, "should report 10 tracks")
        XCTAssertEqual(numUIDs, 10, "should report 10 UIDs")
        // 4 bytes header + 40 bytes per UID = 4 + 10*40 = 404 bytes
        XCTAssertEqual(chnaSize, 404, "chna payload size = 4 + 10*40")
    }
}
