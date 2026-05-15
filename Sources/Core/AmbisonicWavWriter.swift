import Foundation

/// Writes 4-channel 24-bit PCM WAV with an iXML chunk declaring AmbiX (ACN/SN3D, 1st-order)
/// ambisonic format. Used to write the `source.wav` sidecar.
///
/// Usage: instantiate → call `appendFrames` repeatedly → call `finalize` exactly once.
///
/// Not thread-safe.
public final class AmbisonicWavWriter {
    private let url: URL
    private let sampleRate: Int
    private let bitsPerSample: Int
    private let channelCount: Int = 4
    private let handle: FileHandle
    private var framesWritten: Int = 0
    private var finalized = false

    private let ixmlPayload: Data = {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <BWFXML>
          <IXML_VERSION>1.5</IXML_VERSION>
          <PROJECT>Spatial Field Converter</PROJECT>
          <AMBISONIC>AmbiX 1st-order ACN/SN3D</AMBISONIC>
          <CHANNEL_ORDER>ACN</CHANNEL_ORDER>
          <NORMALIZATION>SN3D</NORMALIZATION>
          <ORDER>1</ORDER>
        </BWFXML>
        """
        return xml.data(using: .utf8) ?? Data()
    }()

    public init(url: URL, sampleRate: Int, bitsPerSample: Int) throws {
        precondition(bitsPerSample == 24, "v0.1 only emits 24-bit ambisonic source")
        self.url = url
        self.sampleRate = sampleRate
        self.bitsPerSample = bitsPerSample
        FileManager.default.createFile(atPath: url.path, contents: nil)
        self.handle = try FileHandle(forWritingTo: url)
        try writePlaceholderHeader()
    }

    private func writePlaceholderHeader() throws {
        // Layout:
        //   [12 bytes RIFF header]
        //   [24 bytes fmt chunk]
        //   [8 + iXML payload + pad iXML chunk]
        //   [8 bytes data chunk header — size patched in finalize()]
        let ixmlSize = ixmlPayload.count
        let ixmlPad = ixmlSize % 2

        var data = Data()
        data.append("RIFF".data(using: .ascii)!)
        data.append(le32(0))                             // placeholder, patched in finalize
        data.append("WAVE".data(using: .ascii)!)

        let bytesPerSample = bitsPerSample / 8
        let byteRate = sampleRate * channelCount * bytesPerSample
        let blockAlign = channelCount * bytesPerSample

        data.append("fmt ".data(using: .ascii)!)
        data.append(le32(16))
        data.append(le16(1))                             // PCM
        data.append(le16(UInt16(channelCount)))
        data.append(le32(UInt32(sampleRate)))
        data.append(le32(UInt32(byteRate)))
        data.append(le16(UInt16(blockAlign)))
        data.append(le16(UInt16(bitsPerSample)))

        data.append("iXML".data(using: .ascii)!)
        data.append(le32(UInt32(ixmlSize)))
        data.append(ixmlPayload)
        if ixmlPad == 1 { data.append(UInt8(0)) }

        data.append("data".data(using: .ascii)!)
        data.append(le32(0))                             // placeholder, patched in finalize

        try handle.seek(toOffset: 0)
        handle.write(data)
    }

    public func appendFrames(_ floats: [Float], frameCount: Int) throws {
        precondition(floats.count >= frameCount * channelCount, "buffer too small")
        var bytes = Data(capacity: frameCount * channelCount * 3)
        for i in 0..<(frameCount * channelCount) {
            let clamped = max(-1.0, min(1.0, floats[i]))
            let intVal = Int32(clamped * Float(0x7FFFFF))
            bytes.append(UInt8(intVal & 0xFF))
            bytes.append(UInt8((intVal >> 8) & 0xFF))
            bytes.append(UInt8((intVal >> 16) & 0xFF))
        }
        handle.write(bytes)
        framesWritten += frameCount
    }

    public func finalize() throws {
        guard !finalized else { return }
        finalized = true

        let dataSize = framesWritten * channelCount * (bitsPerSample / 8)
        let ixmlSize = ixmlPayload.count
        let ixmlPad = ixmlSize % 2
        // RIFF size = total file size - 8 (RIFF header + size field itself)
        let riffSize = 4                                  // "WAVE"
            + 8 + 16                                      // fmt header + payload
            + 8 + ixmlSize + ixmlPad                      // iXML chunk
            + 8 + dataSize                                // data chunk

        try handle.seek(toOffset: 4)
        handle.write(le32(UInt32(riffSize)))

        // data size offset: 12 (RIFF) + 24 (fmt) + 8 (iXML header) + ixmlSize + ixmlPad + 4 (data id)
        let dataSizeOffset: UInt64 = UInt64(12 + 24 + 8 + ixmlSize + ixmlPad + 4)
        try handle.seek(toOffset: dataSizeOffset)
        handle.write(le32(UInt32(dataSize)))
        try handle.close()
    }
}

// MARK: - Little-endian helpers (file-private)

private func le16(_ value: UInt16) -> Data {
    var v = value.littleEndian
    return Data(bytes: &v, count: 2)
}

private func le32(_ value: UInt32) -> Data {
    var v = value.littleEndian
    return Data(bytes: &v, count: 4)
}
