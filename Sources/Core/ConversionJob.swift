import Foundation

/// Source mic type — determines which A→B-format decode matrix to apply.
/// v0.1 supports Zoom VRH-8 (A-format) and passthrough (file is already B-format AmbiX).
public enum SourceMicType: String, Sendable {
    case vrh8AFormat = "Zoom VRH-8 (A-format)"
    case alreadyBFormat = "B-format AmbiX (passthrough)"

    /// Returns the A→B-format decode matrix, or nil if input is already B-format.
    public var decodeMatrix: [[Float]]? {
        switch self {
        case .vrh8AFormat: return VRH8DecoderMatrix.matrix
        case .alreadyBFormat: return nil
        }
    }
}

public enum ConversionJobError: Error, CustomStringConvertible {
    case wrongChannelCount(Int)
    case unsupportedSampleRate(Int)

    public var description: String {
        switch self {
        case .wrongChannelCount(let n):
            return "expected 4-channel ambisonic input, found \(n) channels"
        case .unsupportedSampleRate(let r):
            return "expected 48000 Hz sample rate, found \(r) Hz"
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

    private let chunkFrames: Int = 4800   // 100 ms at 48 kHz

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
        guard metadata.channelCount == 4 else {
            throw ConversionJobError.wrongChannelCount(metadata.channelCount)
        }
        guard metadata.sampleRate == 48000 else {
            throw ConversionJobError.unsupportedSampleRate(metadata.sampleRate)
        }

        // 2. Slug + output path
        let recordedAt = Self.parseRecordedAt(metadata: metadata)
            ?? Self.fileModificationDate(of: sourceFile)
            ?? Date()
        let slug = Self.makeSlug(for: sourceFile, title: programmeName, recordedAt: recordedAt)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let outputURL = outputDirectory.appendingPathComponent("\(slug).wav")

        // 3. Streaming pipeline: read → A→B → B→7.1.2 → ADM BWF write
        let sampleReader = try WavSampleReader(reader: reader)
        let aFormatDecoder = AmbisonicDecoder(matrix: mic.decodeMatrix ?? identityMatrix4x4())
        let rig = VirtualLoudspeakerRig.atmos7_1_2()
        let streamingDecoder = rig.makeStreamingDecoder(sampleRate: 48000)

        let admSession = ADMBedSession(programmeName: programmeName)
        let admWriter = try ADMBWFWriter(url: outputURL, session: admSession)

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

            // Write bed frames into the ADM BWF
            try admWriter.appendBedFrames(bed, frameCount: block.frameCount)
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
