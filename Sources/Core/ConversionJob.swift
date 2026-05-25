import Foundation

/// Source mic type — determines which decode path to use.
/// v0.1 supports Zoom VRH-8 (A-format, 4ch), Sennheiser Ambeo VR (A-format, 4ch),
/// B-format AmbiX passthrough (4ch), and Zylia ZM-1 / 3rd-order AmbiX (16ch).
public enum SourceMicType: String, Sendable, CaseIterable {
    case vrh8AFormat     = "Zoom VRH-8 (A-format)"
    case ambeoAFormat    = "Sennheiser Ambeo VR (A-format)"
    case alreadyBFormat  = "B-format AmbiX 1st-order (passthrough)"
    case ambixThirdOrder = "B-format AmbiX 3rd-order (Zylia)"

    /// Returns the A→B-format decode matrix for 1st-order paths, or nil otherwise.
    public var decodeMatrix: [[Float]]? {
        switch self {
        case .vrh8AFormat:     return VRH8DecoderMatrix.matrix
        case .ambeoAFormat:    return AmbeoDecoderMatrix.matrix
        case .alreadyBFormat:  return nil
        case .ambixThirdOrder: return nil   // HOA path uses HigherOrderAmbisonicDecoder
        }
    }
}

public enum ConversionJobError: Error, CustomStringConvertible {
    case wrongChannelCount(Int)
    case unsupportedSampleRate(Int)
    case channelCountMicTypeMismatch(channelCount: Int, mic: SourceMicType)

    public var description: String {
        switch self {
        case .wrongChannelCount(let n):
            return "unsupported channel count: \(n) (expected 4 or 16)"
        case .unsupportedSampleRate(let r):
            return "expected 48000 Hz sample rate, found \(r) Hz"
        case .channelCountMicTypeMismatch(let n, let mic):
            return "channel count \(n) does not match mic type '\(mic.rawValue)'"
        }
    }
}

/// Result of a completed conversion. The ADM BWF master file is at `admBwfURL`.
public struct ConversionJobResult: Sendable {
    public let admBwfURL: URL
    public let slug: String
    public let durationSeconds: Double
}

/// Orchestrates the H8 .wav → ADM BWF master pipeline.
/// Streaming: reads the source in chunks, decodes A→B-format, decodes B-format→7.1.2 bed
/// (with LFE low-pass), writes 24-bit PCM into the ADM BWF master.
///
/// Memory: per-chunk buffer of ~100ms (4800 frames). Long recordings stream cleanly.
public final class ConversionJob: @unchecked Sendable {

    public let sourceFile: URL
    public let outputDirectory: URL
    public let mic: SourceMicType
    public let programmeName: String
    public let converterVersion: String

    // 1 second at 48 kHz. Was 4800 (100 ms) in v1.1.0–v1.1.10 — 10× more
    // per-chunk overhead (Swift call + buffer alloc + file handle write)
    // than necessary. 48000 × 16 channels × 4 bytes = 3 MB peak buffer,
    // safely small relative to system memory.
    private let chunkFrames: Int = 48000

    public init(
        sourceFile: URL,
        outputDirectory: URL,
        mic: SourceMicType,
        programmeName: String,
        converterVersion: String
    ) {
        self.sourceFile = sourceFile
        self.outputDirectory = outputDirectory
        self.mic = mic
        self.programmeName = programmeName
        self.converterVersion = converterVersion
    }

    public func run() async throws -> ConversionJobResult {
        // 1. Read source
        let reader = try WavFileReader(url: sourceFile)
        let metadata = reader.metadata
        let channelCount = metadata.channelCount
        guard channelCount == 4 || channelCount == 16 else {
            throw ConversionJobError.wrongChannelCount(channelCount)
        }
        guard metadata.sampleRate == 48000 else {
            throw ConversionJobError.unsupportedSampleRate(metadata.sampleRate)
        }
        // Validate mic type matches channel count
        if mic == .ambixThirdOrder && channelCount != 16 {
            throw ConversionJobError.channelCountMicTypeMismatch(channelCount: channelCount, mic: mic)
        }
        if (mic == .vrh8AFormat || mic == .ambeoAFormat || mic == .alreadyBFormat) && channelCount != 4 {
            throw ConversionJobError.channelCountMicTypeMismatch(channelCount: channelCount, mic: mic)
        }

        // 2. Slug + output path
        let recordedAt = Self.parseRecordedAt(metadata: metadata)
            ?? Self.fileModificationDate(of: sourceFile)
            ?? Date()
        let slug = Self.makeSlug(for: sourceFile, title: programmeName, recordedAt: recordedAt)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let outputURL = outputDirectory.appendingPathComponent("\(slug).wav")

        let admSession = ADMBedSession(programmeName: programmeName)
        let admWriter = try ADMBWFWriter(url: outputURL, session: admSession)
        let sampleReader = try WavSampleReader(reader: reader)

        if mic == .ambixThirdOrder {
            // 3a. HOA path: 16-ch AmbiX 3rd-order → 7.1.2 bed
            let hoaDecoder = HigherOrderAmbisonicDecoder(
                order: .third,
                speakerPositions: VirtualLoudspeakerRig.atmos7_1_2().speakerPositions
            )
            let streamingHOA = hoaDecoder.makeStreamingDecoder(sampleRate: 48000)

            while let block = try sampleReader.readNextBlock(maxFrames: chunkFrames) {
                // Input is already B-format AmbiX 16-ch — no A→B step needed
                let bed = streamingHOA.process(interleavedAmbisonic: block.samples, frameCount: block.frameCount)
                try admWriter.appendBedFrames(bed, frameCount: block.frameCount)
            }
        } else {
            // 3b. 1st-order path: read → A→B (or passthrough) → B→7.1.2 → ADM BWF write
            let aFormatDecoder = AmbisonicDecoder(matrix: mic.decodeMatrix ?? identityMatrix4x4())
            let rig = VirtualLoudspeakerRig.atmos7_1_2()
            let streamingDecoder = rig.makeStreamingDecoder(sampleRate: 48000)

            while let block = try sampleReader.readNextBlock(maxFrames: chunkFrames) {
                // A → B-format (or passthrough)
                let bformat: [Float]
                if mic.decodeMatrix != nil {
                    bformat = aFormatDecoder.decode(interleavedAFormat: block.samples, frameCount: block.frameCount)
                } else {
                    bformat = block.samples
                }

                // B-format → 7.1.2 bed (with LFE low-pass)
                let bed = streamingDecoder.process(interleavedBformat: bformat, frameCount: block.frameCount)
                try admWriter.appendBedFrames(bed, frameCount: block.frameCount)
            }
        }

        try admWriter.finalize()

        return ConversionJobResult(
            admBwfURL: outputURL,
            slug: slug,
            durationSeconds: metadata.durationSeconds
        )
    }

    // MARK: - Helpers

    /// Identity 4×4 matrix (used for passthrough mode).
    private func identityMatrix4x4() -> [[Float]] {
        return [
            [1, 0, 0, 0],
            [0, 1, 0, 0],
            [0, 0, 1, 0],
            [0, 0, 0, 1],
        ]
    }

    /// Slug = `<sanitized-title>-YYYY-MM-DD-<6-char-hex>` deterministic for same input file + title.
    /// The user's editable title in the inspector drives the slug; H8 default filenames
    /// (e.g. "MIC1234") are still usable but get sanitized.
    static func makeSlug(for url: URL, title: String, recordedAt: Date) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        let dateStr = dateFormatter.string(from: recordedAt)

        let titleSlug = Self.sanitizeForSlug(title)
        let prefix = titleSlug.isEmpty ? "field-recording" : titleSlug

        // Simple hash: filename + recordedAt. Doesn't need to be cryptographic for v0.1.
        var h: UInt64 = 14695981039346656037   // FNV-1a offset basis
        for byte in url.lastPathComponent.utf8 {
            h = (h ^ UInt64(byte)) &* 1099511628211
        }
        let recordedAtBytes = Int64(recordedAt.timeIntervalSince1970).bigEndian
        withUnsafeBytes(of: recordedAtBytes) { ptr in
            for byte in ptr {
                h = (h ^ UInt64(byte)) &* 1099511628211
            }
        }
        let hex6 = String(format: "%06x", h & 0xFFFFFF)

        return "\(prefix)-\(dateStr)-\(hex6)"
    }

    /// Sanitize a user-typed title into a slug-safe ASCII prefix.
    /// Rules: lowercase, replace whitespace with dash, strip non-alphanumeric/non-dash,
    /// collapse multiple dashes, trim leading/trailing dashes, max 40 chars.
    /// Returns "" if the input is empty after sanitization (caller falls back to a generic prefix).
    static func sanitizeForSlug(_ raw: String) -> String {
        let lower = raw.lowercased()
        var out = ""
        var lastDash = true   // collapse leading dashes too
        for ch in lower.unicodeScalars {
            let isAlnum = (ch >= "a" && ch <= "z") || (ch >= "0" && ch <= "9")
            if isAlnum {
                out.unicodeScalars.append(ch)
                lastDash = false
            } else {
                if !lastDash {
                    out.append("-")
                    lastDash = true
                }
            }
            if out.count >= 40 { break }
        }
        // Trim trailing dash
        while out.hasSuffix("-") { out.removeLast() }
        return out
    }

    static func parseRecordedAt(metadata: WavMetadata) -> Date? {
        guard let date = metadata.bextOriginationDate?.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters)),
              let time = metadata.bextOriginationTime?.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters)),
              !date.isEmpty, !time.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.date(from: "\(date) \(time)")
    }

    static func fileModificationDate(of url: URL) -> Date? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attrs?[.modificationDate] as? Date
    }
}
