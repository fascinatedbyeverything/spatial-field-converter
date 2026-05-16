import Accelerate
import Foundation

/// Writes a Dolby Atmos Master ADM BWF .wav with a 7.1.2 bed pack (10 channels, 24-bit, 48 kHz).
///
/// Format:
///   RIFF header
///   fmt chunk (PCM, 10ch, 48k, 24-bit)
///   axml chunk (UTF-8 XML, audioFormatExtended root, BS.2094 7.1.2 references)
///   chna chunk (binary channel-to-audioTrackUID mapping, 40 bytes per UID × 10)
///   data chunk (interleaved 24-bit PCM samples)
///
/// Usage: instantiate → call `appendBedFrames` repeatedly → call `finalize` exactly once.
///
/// Not thread-safe.
public final class ADMBWFWriter {
    public enum Error: Swift.Error {
        case unsupportedSampleRate
        case finalizeFailed(String)
    }

    private let url: URL
    private let session: ADMBedSession
    private let handle: FileHandle
    private let channelCount: Int = ADMBedConfig.channelCount
    private let bitsPerSample: Int = 24
    private var framesWritten: Int = 0
    private var finalized = false

    /// axml payload built at init with placeholder duration (all zeros).
    /// At finalize we rebuild with the real duration and verify byte count matches.
    private let axmlPayload: Data

    /// chna payload — 4-byte header + 40 bytes × 10 UIDs = 404 bytes.
    private let chnaPayload: Data

    public init(url: URL, session: ADMBedSession) throws {
        self.url = url
        self.session = session

        // Build axml with placeholder duration 0.0. We rebuild at finalize with real duration.
        // formatADMTime always produces a 14-character string so byte counts stay equal.
        self.axmlPayload = ADMBWFWriter.buildAxml(programmeName: session.programmeName,
                                                  durationSec: 0.0)
        self.chnaPayload = ADMBWFWriter.buildChna()

        FileManager.default.createFile(atPath: url.path, contents: nil)
        self.handle = try FileHandle(forWritingTo: url)
        try writePlaceholderHeader()
    }

    /// Append interleaved bed frames. `floats` must have at least `frameCount × 10` elements.
    /// Audio is clamped to [-1, 1] and encoded as 24-bit signed integer PCM (little-endian).
    ///
    /// Scale+clamp uses vDSP_vsmul + vDSP_vclip (vectorised); byte-pack stays scalar
    /// because there is no 24-bit SIMD primitive.
    public func appendBedFrames(_ floats: [Float], frameCount: Int) throws {
        let totalSamples = frameCount * channelCount
        precondition(floats.count >= totalSamples, "buffer too small")

        // Scale [-1, +1] → [-0x7FFFFF, +0x7FFFFF]
        var scaled = [Float](repeating: 0, count: totalSamples)
        var scale: Float = Float(0x7FFFFF)
        vDSP_vsmul(floats, 1, &scale, &scaled, 1, vDSP_Length(totalSamples))

        // Clamp to [-0x7FFFFF, +0x7FFFFF] to guard against overshoot
        var lower: Float = -Float(0x7FFFFF)
        var upper: Float =  Float(0x7FFFFF)
        vDSP_vclip(scaled, 1, &lower, &upper, &scaled, 1, vDSP_Length(totalSamples))

        // Pack to interleaved 24-bit little-endian (3 bytes per sample)
        var bytes = Data(count: totalSamples * 3)
        bytes.withUnsafeMutableBytes { rawPtr in
            let p = rawPtr.bindMemory(to: UInt8.self).baseAddress!
            for i in 0..<totalSamples {
                let v = Int32(scaled[i])   // truncates toward zero; already clamped
                p[i * 3 + 0] = UInt8(v & 0xFF)
                p[i * 3 + 1] = UInt8((v >> 8) & 0xFF)
                p[i * 3 + 2] = UInt8((v >> 16) & 0xFF)
            }
        }

        handle.write(bytes)
        framesWritten += frameCount
    }

    /// Patch RIFF + data sizes, overwrite axml with real duration. Must be called exactly once.
    public func finalize() throws {
        guard !finalized else { return }
        finalized = true

        let dataSize = framesWritten * channelCount * (bitsPerSample / 8)
        let durationSec = Double(framesWritten) / Double(session.sampleRate.rawValue)

        // Rebuild axml with the real duration and verify it's the same byte count.
        let newAxml = ADMBWFWriter.buildAxml(programmeName: session.programmeName, durationSec: durationSec)
        guard newAxml.count == axmlPayload.count else {
            throw Error.finalizeFailed(
                "axml size changed at finalize: was \(axmlPayload.count), now \(newAxml.count). " +
                "Duration formatting must produce equal-length strings."
            )
        }

        // Patch axml payload in-place.
        // Layout: RIFF(12) + fmt(8+16) + axml_id+size(8) = offset 44 for axml payload start.
        let axmlPayloadOffset: UInt64 = 12 + 24 + 8
        try handle.seek(toOffset: axmlPayloadOffset)
        handle.write(newAxml)

        // Compute padding.
        let axmlSize = newAxml.count
        let axmlPad = axmlSize % 2
        let chnaSize = chnaPayload.count
        let chnaPad = chnaSize % 2

        // Patch RIFF size (bytes 4..7).
        let riffPayloadSize = 4                             // "WAVE"
            + 8 + 16                                        // fmt chunk
            + 8 + axmlSize + axmlPad                        // axml chunk
            + 8 + chnaSize + chnaPad                        // chna chunk
            + 8 + dataSize                                  // data chunk

        try handle.seek(toOffset: 4)
        handle.write(UInt32(riffPayloadSize).leData)

        // Patch data chunk size.
        // data chunk id+size field starts after: RIFF(12) + fmt(24) + axml(8+axmlSize+axmlPad) + chna(8+chnaSize+chnaPad) + "data"(4)
        let dataSizeOffset: UInt64 = 12 + 24
            + 8 + UInt64(axmlSize) + UInt64(axmlPad)
            + 8 + UInt64(chnaSize) + UInt64(chnaPad)
            + 4   // skip past "data" id, land on size field
        try handle.seek(toOffset: dataSizeOffset)
        handle.write(UInt32(dataSize).leData)

        try handle.close()
    }

    // MARK: - Header construction

    private func writePlaceholderHeader() throws {
        var data = Data()

        // RIFF header
        data.append("RIFF".data(using: .ascii)!)
        data.append(UInt32(0).leData)           // patched in finalize
        data.append("WAVE".data(using: .ascii)!)

        // fmt chunk (16-byte payload, PCM = format tag 1)
        let sr = session.sampleRate.rawValue
        let bytesPerSample = bitsPerSample / 8
        let byteRate = sr * channelCount * bytesPerSample
        let blockAlign = channelCount * bytesPerSample
        data.append("fmt ".data(using: .ascii)!)
        data.append(UInt32(16).leData)
        data.append(UInt16(1).leData)           // PCM
        data.append(UInt16(channelCount).leData)
        data.append(UInt32(sr).leData)
        data.append(UInt32(byteRate).leData)
        data.append(UInt16(blockAlign).leData)
        data.append(UInt16(bitsPerSample).leData)

        // axml chunk
        let axmlSize = axmlPayload.count
        data.append("axml".data(using: .ascii)!)
        data.append(UInt32(axmlSize).leData)
        data.append(axmlPayload)
        if axmlSize % 2 == 1 { data.append(UInt8(0)) }

        // chna chunk
        let chnaSize = chnaPayload.count
        data.append("chna".data(using: .ascii)!)
        data.append(UInt32(chnaSize).leData)
        data.append(chnaPayload)
        if chnaSize % 2 == 1 { data.append(UInt8(0)) }

        // data chunk header — size is 0, patched in finalize
        data.append("data".data(using: .ascii)!)
        data.append(UInt32(0).leData)

        try handle.seek(toOffset: 0)
        handle.write(data)
    }

    // MARK: - axml construction

    /// Builds the axml XML payload as UTF-8 data using Foundation's XMLDocument.
    ///
    /// Duration is formatted as `HH:MM:SS.SSSSS` — always exactly 14 characters —
    /// so rebuilding with a different duration value produces identical byte-count output.
    static func buildAxml(programmeName: String, durationSec: Double) -> Data {
        let dur = formatADMTime(seconds: durationSec)
        let startTime = "00:00:00.00000"

        let root = XMLElement(name: "audioFormatExtended")
        root.addAttribute(attr("version", "ITU-R_BS.2076-1"))

        // audioProgramme
        let programme = XMLElement(name: "audioProgramme")
        programme.addAttribute(attr("audioProgrammeID", "APR_1001"))
        programme.addAttribute(attr("audioProgrammeName", programmeName))
        programme.addAttribute(attr("start", startTime))
        programme.addAttribute(attr("end", dur))
        programme.addChild(XMLElement(name: "audioContentIDRef", stringValue: "ACO_1001"))
        root.addChild(programme)

        // audioContent
        let content = XMLElement(name: "audioContent")
        content.addAttribute(attr("audioContentID", "ACO_1001"))
        content.addAttribute(attr("audioContentName", "Bed"))
        content.addChild(XMLElement(name: "audioObjectIDRef", stringValue: "AO_1001"))
        root.addChild(content)

        // audioObject
        let obj = XMLElement(name: "audioObject")
        obj.addAttribute(attr("audioObjectID", "AO_1001"))
        obj.addAttribute(attr("audioObjectName", "Bed_7_1_2"))
        obj.addAttribute(attr("start", startTime))
        obj.addAttribute(attr("duration", dur))
        obj.addChild(XMLElement(name: "audioPackFormatIDRef", stringValue: ADMBedConfig.packFormatID))
        for i in 1...ADMBedConfig.channelCount {
            let uid = String(format: "ATU_%08d", i)
            obj.addChild(XMLElement(name: "audioTrackUIDRef", stringValue: uid))
        }
        root.addChild(obj)

        // audioTrackUID per channel
        for (i, channel) in ADMBedConfig.channels.enumerated() {
            let uid = String(format: "ATU_%08d", i + 1)
            let track = XMLElement(name: "audioTrackUID")
            track.addAttribute(attr("UID", uid))
            track.addAttribute(attr("sampleRate", "48000"))
            track.addAttribute(attr("bitDepth", "24"))

            // channelFormatID "AC_00010001" → trackFormatID "AT_00010001_01"
            let channelID = channel.channelFormatID          // e.g. "AC_00010001"
            let numericSuffix = String(channelID.suffix(8))  // e.g. "00010001"
            let trackFormatID = "AT_\(numericSuffix)_01"     // e.g. "AT_00010001_01"
            track.addChild(XMLElement(name: "audioTrackFormatIDRef", stringValue: trackFormatID))
            track.addChild(XMLElement(name: "audioPackFormatIDRef", stringValue: ADMBedConfig.packFormatID))
            root.addChild(track)
        }

        let doc = XMLDocument(rootElement: root)
        doc.version = "1.0"
        doc.characterEncoding = "UTF-8"

        // .nodePrettyPrint ensures stable, human-readable output.
        // .documentTidyXML normalises whitespace/indenting deterministically.
        return doc.xmlData(options: [.nodePrettyPrint, .documentTidyXML])
    }

    // MARK: - chna construction

    /// Builds the chna binary payload.
    /// Total: 4 bytes (numTracks + numUIDs) + 10 × 40 bytes = 404 bytes.
    static func buildChna() -> Data {
        var data = Data()

        let numTracks = UInt16(ADMBedConfig.channelCount)
        let numUIDs   = UInt16(ADMBedConfig.channelCount)
        data.append(numTracks.leData)
        data.append(numUIDs.leData)

        for (i, channel) in ADMBedConfig.channels.enumerated() {
            var entry = Data()

            // Offset 0: trackIndex (uint16, 1-based) — 2 bytes
            entry.append(UInt16(i + 1).leData)

            // Offset 2: uid — 12 ASCII bytes, e.g. "ATU_00000001"
            let uid = String(format: "ATU_%08d", i + 1)
            let uidBytes = Data(uid.utf8)
            assert(uidBytes.count == 12, "UID must be exactly 12 ASCII bytes: '\(uid)'")
            entry.append(uidBytes)

            // Offset 14: trackFormatRef — 14 ASCII bytes, e.g. "AT_00010001_01"
            let numericSuffix = String(channel.channelFormatID.suffix(8))
            let trackFormatRef = "AT_\(numericSuffix)_01"
            let trackFormatBytes = Data(trackFormatRef.utf8)
            assert(trackFormatBytes.count == 14,
                   "trackFormatRef must be exactly 14 ASCII bytes: '\(trackFormatRef)'")
            entry.append(trackFormatBytes)

            // Offset 28: packFormatRef — 11 ASCII bytes, e.g. "AP_00010003"
            let packFormatRef = ADMBedConfig.packFormatID   // "AP_00010003" = exactly 11 chars
            let packFormatBytes = Data(packFormatRef.utf8)
            assert(packFormatBytes.count == 11,
                   "packFormatRef must be exactly 11 ASCII bytes: '\(packFormatRef)'")
            entry.append(packFormatBytes)

            // Offset 39: space padding (0x20) — 1 byte
            entry.append(UInt8(0x20))

            assert(entry.count == 40, "chna entry must be exactly 40 bytes, got \(entry.count)")
            data.append(entry)
        }

        assert(data.count == 404, "chna payload must be 4 + 10×40 = 404 bytes, got \(data.count)")
        return data
    }

    // MARK: - Time formatting

    /// Formats seconds as `HH:MM:SS.SSSSS` — exactly 14 characters.
    ///
    /// The fixed width is critical: it ensures `buildAxml` produces identical byte-count
    /// output whether called with `durationSec = 0.0` (init) or the real duration (finalize).
    static func formatADMTime(seconds: Double) -> String {
        let totalMicros = Int64((seconds * 1_000_000).rounded())
        let micros     = totalMicros % 1_000_000
        let totalSec   = totalMicros / 1_000_000
        let secs       = totalSec % 60
        let mins       = (totalSec / 60) % 60
        let hours      = totalSec / 3600
        // Five sub-second digits = centimicroseconds (micros / 10, range 0–99999).
        return String(format: "%02d:%02d:%02d.%05d", hours, mins, secs, micros / 10)
    }
}

// MARK: - Little-endian Data helpers (file-private)

private extension FixedWidthInteger {
    var leData: Data {
        var v = self.littleEndian
        return Data(bytes: &v, count: MemoryLayout<Self>.size)
    }
}

private func attr(_ name: String, _ value: String) -> XMLNode {
    XMLNode.attribute(withName: name, stringValue: value) as! XMLNode
}
