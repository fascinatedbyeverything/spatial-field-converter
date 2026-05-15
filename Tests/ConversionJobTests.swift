import XCTest
@testable import SpatialFieldConverter

final class ConversionJobTests: XCTestCase {
    var tempDir: URL!

    override func setUp() { super.setUp(); tempDir = TempDirectory.makeUnique() }
    override func tearDown() { TempDirectory.cleanup(tempDir); super.tearDown() }

    func test_endToEnd_produces10ChannelAdmBwfFromSyntheticH8File() async throws {
        // 1. Create a synthetic H8 A-format input file (4-ch 24-bit 48kHz, ~0.5s)
        let inputURL = tempDir.appendingPathComponent("ZOOM0001.WAV")
        try writeSyntheticAFormatWav(at: inputURL, durationSeconds: 0.5)

        // 2. Configure and run the conversion
        let outputDir = tempDir.appendingPathComponent("output")
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        let job = ConversionJob(
            sourceFile: inputURL,
            outputDirectory: outputDir,
            mic: .vrh8AFormat,
            programmeName: "Test Field Recording",
            converterVersion: "0.1.0-test"
        )
        let result = try await job.run()

        // 3. Verify the ADM BWF output
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.admBwfURL.path),
                      "ADM BWF master must exist at \(result.admBwfURL.path)")

        let reader = try WavFileReader(url: result.admBwfURL)
        XCTAssertEqual(reader.metadata.channelCount, 10,
                       "ADM BWF must be 10-channel 7.1.2 bed")
        XCTAssertEqual(reader.metadata.sampleRate, 48000)
        XCTAssertEqual(reader.metadata.bitsPerSample, 24)
        XCTAssertEqual(reader.metadata.frameCount, 24000,
                       "Frame count should match 0.5s × 48kHz = 24000")

        // axml + chna chunks present
        let raw = try Data(contentsOf: result.admBwfURL)
        XCTAssertTrue(raw.contains("audioFormatExtended".data(using: .ascii)!))
        XCTAssertTrue(raw.contains("AP_00010003".data(using: .ascii)!), "7.1.2 pack ID present")
        XCTAssertTrue(raw.contains("Test Field Recording".data(using: .ascii)!),
                      "programme name embedded in axml")

        // Slug derived from sanitized title "Test Field Recording" → "test-field-recording"
        XCTAssertTrue(result.slug.hasPrefix("test-field-recording-"),
                      "slug should be derived from the user-editable title: \(result.slug)")
        XCTAssertGreaterThan(result.durationSeconds, 0.49)
        XCTAssertLessThan(result.durationSeconds, 0.51)
    }

    func test_rejects_nonAmbisonicWavFile() async throws {
        // Stereo file should be rejected — converter only handles 4-ch ambisonic
        let inputURL = tempDir.appendingPathComponent("stereo.wav")
        try writeStereoSilence(at: inputURL, durationSeconds: 1.0)

        let job = ConversionJob(
            sourceFile: inputURL,
            outputDirectory: tempDir.appendingPathComponent("out"),
            mic: .vrh8AFormat,
            programmeName: "stereo",
            converterVersion: "0.1.0-test"
        )

        do {
            _ = try await job.run()
            XCTFail("expected throw")
        } catch ConversionJobError.wrongChannelCount(let n) {
            XCTAssertEqual(n, 2)
        }
    }

    // MARK: - Test helpers

    private func writeSyntheticAFormatWav(at url: URL, durationSeconds: Double) throws {
        let sampleRate = 48000
        let frameCount = Int(durationSeconds * Double(sampleRate))
        let aformat = SyntheticAmbisonicSignals.aFormatNoise(frameCount: frameCount)
        try writeInterleavedFloatAsWav24bit(at: url, channels: 4, sampleRate: sampleRate, samples: aformat)
    }

    private func writeStereoSilence(at url: URL, durationSeconds: Double) throws {
        let sampleRate = 48000
        let frameCount = Int(durationSeconds * Double(sampleRate))
        let samples = [Float](repeating: 0, count: frameCount * 2)
        try writeInterleavedFloatAsWav24bit(at: url, channels: 2, sampleRate: sampleRate, samples: samples)
    }

    private func writeInterleavedFloatAsWav24bit(at url: URL, channels: Int, sampleRate: Int, samples: [Float]) throws {
        var pcm = Data()
        for s in samples {
            let clamped = max(-1.0, min(1.0, s))
            let v = Int32(clamped * Float(0x7FFFFF))
            pcm.append(UInt8(v & 0xFF))
            pcm.append(UInt8((v >> 8) & 0xFF))
            pcm.append(UInt8((v >> 16) & 0xFF))
        }
        let bytesPerSample = 3
        let dataSize = pcm.count
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
        data.append(UInt16(24).littleEndianData)
        data.append("data".data(using: .ascii)!)
        data.append(UInt32(dataSize).littleEndianData)
        data.append(pcm)
        try data.write(to: url)
    }
}
