import XCTest
@testable import SpatialFieldConverter

final class WavFileReaderTests: XCTestCase {
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = TempDirectory.makeUnique()
    }

    override func tearDown() {
        TempDirectory.cleanup(tempDir)
        super.tearDown()
    }

    func test_parsesRiffHeader_4channel_48kHz_24bit() throws {
        let url = tempDir.appendingPathComponent("test.wav")
        try writeMinimalWav(at: url, channels: 4, sampleRate: 48000, bitDepth: 24, frameCount: 100)

        let reader = try WavFileReader(url: url)
        let meta = reader.metadata

        XCTAssertEqual(meta.channelCount, 4)
        XCTAssertEqual(meta.sampleRate, 48000)
        XCTAssertEqual(meta.bitsPerSample, 24)
        XCTAssertEqual(meta.frameCount, 100)
    }

    private func writeMinimalWav(at url: URL, channels: Int, sampleRate: Int, bitDepth: Int, frameCount: Int) throws {
        let bytesPerSample = bitDepth / 8
        let dataSize = frameCount * channels * bytesPerSample
        let byteRate = sampleRate * channels * bytesPerSample
        let blockAlign = channels * bytesPerSample

        var data = Data()
        data.append("RIFF".data(using: .ascii)!)
        data.append(UInt32(36 + dataSize).littleEndianData)
        data.append("WAVE".data(using: .ascii)!)

        data.append("fmt ".data(using: .ascii)!)
        data.append(UInt32(16).littleEndianData)
        data.append(UInt16(1).littleEndianData)
        data.append(UInt16(channels).littleEndianData)
        data.append(UInt32(sampleRate).littleEndianData)
        data.append(UInt32(byteRate).littleEndianData)
        data.append(UInt16(blockAlign).littleEndianData)
        data.append(UInt16(bitDepth).littleEndianData)

        data.append("data".data(using: .ascii)!)
        data.append(UInt32(dataSize).littleEndianData)
        data.append(Data(count: dataSize))

        try data.write(to: url)
    }

    // MARK: - Task 1.2

    func test_extractsBextDescription() throws {
        let url = tempDir.appendingPathComponent("with-bext.wav")
        try writeWavWithBext(at: url, description: "AMBI A-format VRH-8")

        let reader = try WavFileReader(url: url)
        XCTAssertEqual(reader.metadata.bextDescription, "AMBI A-format VRH-8")
    }

    private func writeWavWithBext(at url: URL, description: String) throws {
        let channels = 4
        let sampleRate = 48000
        let bitDepth = 24
        let frameCount = 100
        let bytesPerSample = bitDepth / 8
        let dataSize = frameCount * channels * bytesPerSample
        let byteRate = sampleRate * channels * bytesPerSample
        let blockAlign = channels * bytesPerSample

        var bext = Data(count: 602)
        let descBytes = description.padding(toLength: 256, withPad: "\0", startingAt: 0).data(using: .ascii)!
        bext.replaceSubrange(0..<256, with: descBytes)

        let totalRiffSize = 36 + 8 + bext.count + 8 + dataSize

        var data = Data()
        data.append("RIFF".data(using: .ascii)!)
        data.append(UInt32(totalRiffSize).littleEndianData)
        data.append("WAVE".data(using: .ascii)!)
        data.append("fmt ".data(using: .ascii)!)
        data.append(UInt32(16).littleEndianData)
        data.append(UInt16(1).littleEndianData)
        data.append(UInt16(channels).littleEndianData)
        data.append(UInt32(sampleRate).littleEndianData)
        data.append(UInt32(byteRate).littleEndianData)
        data.append(UInt16(blockAlign).littleEndianData)
        data.append(UInt16(bitDepth).littleEndianData)
        data.append("bext".data(using: .ascii)!)
        data.append(UInt32(bext.count).littleEndianData)
        data.append(bext)
        data.append("data".data(using: .ascii)!)
        data.append(UInt32(dataSize).littleEndianData)
        data.append(Data(count: dataSize))
        try data.write(to: url)
    }

    // MARK: - Task 1.2b — BEXT date/time

    func test_extractsBextDateAndTime() throws {
        // EBU Tech 3285 BEXT layout (verified against the standard):
        //   bytes   0-255: Description (ASCII)
        //   bytes 256-287: Originator (ASCII)
        //   bytes 288-319: OriginatorReference (ASCII)
        //   bytes 320-329: OriginationDate "YYYY-MM-DD"
        //   bytes 330-337: OriginationTime "HH:MM:SS"
        //   bytes 338-...: TimeReferenceLow/High, Version, UMID, etc.
        let url = tempDir.appendingPathComponent("with-bext-datetime.wav")
        try writeWavWithBextDateTime(at: url, date: "2026-05-15", time: "10:00:00")

        let reader = try WavFileReader(url: url)
        XCTAssertEqual(reader.metadata.bextOriginationDate, "2026-05-15")
        XCTAssertEqual(reader.metadata.bextOriginationTime, "10:00:00")
    }

    private func writeWavWithBextDateTime(at url: URL, date: String, time: String) throws {
        XCTAssertEqual(date.count, 10, "date must be YYYY-MM-DD format")
        XCTAssertEqual(time.count, 8, "time must be HH:MM:SS format")

        let channels = 4
        let sampleRate = 48000
        let bitDepth = 24
        let frameCount = 100
        let bytesPerSample = bitDepth / 8
        let dataSize = frameCount * channels * bytesPerSample
        let byteRate = sampleRate * channels * bytesPerSample
        let blockAlign = channels * bytesPerSample

        // Minimum BEXT size is 602 bytes (per EBU Tech 3285 v1)
        var bext = Data(count: 602)
        // Fill date at offset 320-329
        let dateBytes = date.data(using: .ascii)!
        bext.replaceSubrange(320..<320 + dateBytes.count, with: dateBytes)
        // Fill time at offset 330-337
        let timeBytes = time.data(using: .ascii)!
        bext.replaceSubrange(330..<330 + timeBytes.count, with: timeBytes)

        let totalRiffSize = 36 + 8 + bext.count + 8 + dataSize

        var data = Data()
        data.append("RIFF".data(using: .ascii)!)
        data.append(UInt32(totalRiffSize).littleEndianData)
        data.append("WAVE".data(using: .ascii)!)
        data.append("fmt ".data(using: .ascii)!)
        data.append(UInt32(16).littleEndianData)
        data.append(UInt16(1).littleEndianData)
        data.append(UInt16(channels).littleEndianData)
        data.append(UInt32(sampleRate).littleEndianData)
        data.append(UInt32(byteRate).littleEndianData)
        data.append(UInt16(blockAlign).littleEndianData)
        data.append(UInt16(bitDepth).littleEndianData)
        data.append("bext".data(using: .ascii)!)
        data.append(UInt32(bext.count).littleEndianData)
        data.append(bext)
        data.append("data".data(using: .ascii)!)
        data.append(UInt32(dataSize).littleEndianData)
        data.append(Data(count: dataSize))
        try data.write(to: url)
    }

    // MARK: - Task 1.3

    func test_readsSamplesAsFloat_24bit() throws {
        let url = tempDir.appendingPathComponent("samples.wav")
        let frameCount = 4
        let channels = 4
        var samples = Data()
        let frames: [[Int32]] = [
            [1, 2, 3, 4],
            [0, 0, 0, 0],
            [0x7FFFFF, 0, 0, 0],
            [Int32(bitPattern: 0xFF800000), 0, 0, 0]
        ]
        for frame in frames {
            for sample in frame {
                samples.append(UInt8(sample & 0xFF))
                samples.append(UInt8((sample >> 8) & 0xFF))
                samples.append(UInt8((sample >> 16) & 0xFF))
            }
        }
        try writeWav(at: url, channels: channels, sampleRate: 48000, bitDepth: 24, sampleData: samples)

        let reader = try WavFileReader(url: url)
        let sampleReader = try WavSampleReader(reader: reader)
        var allFrames: [[Float]] = []
        while let block = try sampleReader.readNextBlock(maxFrames: 1) {
            for f in 0..<block.frameCount {
                var frame: [Float] = []
                for c in 0..<channels {
                    frame.append(block.samples[f * channels + c])
                }
                allFrames.append(frame)
            }
        }

        XCTAssertEqual(allFrames.count, 4)
        XCTAssertEqual(allFrames[0][0], 1.0 / Float(0x800000), accuracy: 1e-9)
        XCTAssertEqual(allFrames[2][0], Float(0x7FFFFF) / Float(0x800000), accuracy: 1e-7)
        XCTAssertEqual(allFrames[3][0], -1.0, accuracy: 1e-7)
    }

    private func writeWav(at url: URL, channels: Int, sampleRate: Int, bitDepth: Int, sampleData: Data) throws {
        let bytesPerSample = bitDepth / 8
        let byteRate = sampleRate * channels * bytesPerSample
        let blockAlign = channels * bytesPerSample
        let dataSize = sampleData.count

        var data = Data()
        data.append("RIFF".data(using: .ascii)!)
        data.append(UInt32(36 + dataSize).littleEndianData)
        data.append("WAVE".data(using: .ascii)!)
        data.append("fmt ".data(using: .ascii)!)
        data.append(UInt32(16).littleEndianData)
        data.append(UInt16(1).littleEndianData)
        data.append(UInt16(channels).littleEndianData)
        data.append(UInt32(sampleRate).littleEndianData)
        data.append(UInt32(byteRate).littleEndianData)
        data.append(UInt16(blockAlign).littleEndianData)
        data.append(UInt16(bitDepth).littleEndianData)
        data.append("data".data(using: .ascii)!)
        data.append(UInt32(dataSize).littleEndianData)
        data.append(sampleData)
        try data.write(to: url)
    }
}

extension FixedWidthInteger {
    var littleEndianData: Data {
        withUnsafeBytes(of: self.littleEndian) { Data($0) }
    }
}
