import Foundation

public struct WavMetadata: Sendable, Equatable {
    public let channelCount: Int
    public let sampleRate: Int
    public let bitsPerSample: Int
    public let frameCount: Int
    public let durationSeconds: Double
    public let dataChunkOffset: Int
    public let dataChunkSize: Int
    public let bextDescription: String?
    public let bextOriginationDate: String?
    public let bextOriginationTime: String?
    public let ixmlContent: String?
}

public enum WavReadError: Error {
    case fileTooSmall
    case missingRiffHeader
    case missingFmtChunk
    case missingDataChunk
    case unsupportedFormat(UInt16)
}

/// Reads a WAV file's RIFF header, format chunk, optional BEXT chunk
/// (Broadcast Wave Format, EBU Tech 3285), and optional iXML chunk.
///
/// Use the published `metadata` to inspect channel layout, sample rate, bit depth,
/// frame count, and any BWF/iXML metadata. To read audio samples, construct a
/// `WavSampleReader` from this reader.
///
/// Not thread-safe.
public final class WavFileReader {
    public let url: URL
    public let metadata: WavMetadata
    private let fileHandle: FileHandle

    public init(url: URL) throws {
        self.url = url
        self.fileHandle = try FileHandle(forReadingFrom: url)
        self.metadata = try Self.parseHeader(handle: fileHandle)
    }

    deinit {
        try? fileHandle.close()
    }

    private static func parseHeader(handle: FileHandle) throws -> WavMetadata {
        try handle.seek(toOffset: 0)
        guard let header = try? handle.read(upToCount: 12), header.count == 12 else {
            throw WavReadError.fileTooSmall
        }
        guard header.subdata(in: 0..<4) == "RIFF".data(using: .ascii),
              header.subdata(in: 8..<12) == "WAVE".data(using: .ascii) else {
            throw WavReadError.missingRiffHeader
        }

        var offset: UInt64 = 12
        var fmt: (channels: Int, sampleRate: Int, bitsPerSample: Int)?
        var dataInfo: (offset: Int, size: Int)?
        var bextDescription: String?
        var bextOriginationDate: String?
        var bextOriginationTime: String?
        var ixmlContent: String?

        while true {
            try handle.seek(toOffset: offset)
            guard let chunkHeader = try? handle.read(upToCount: 8), chunkHeader.count == 8 else { break }
            let id = String(data: chunkHeader.subdata(in: 0..<4), encoding: .ascii) ?? ""
            let size = chunkHeader.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
            let payloadOffset = offset + 8

            switch id {
            case "fmt ":
                try handle.seek(toOffset: payloadOffset)
                guard let payload = try? handle.read(upToCount: Int(size)) else { break }
                let format = payload.subdata(in: 0..<2).withUnsafeBytes { $0.load(as: UInt16.self).littleEndian }
                guard format == 1 || format == 0xFFFE else { throw WavReadError.unsupportedFormat(format) }
                let channels = Int(payload.subdata(in: 2..<4).withUnsafeBytes { $0.load(as: UInt16.self).littleEndian })
                let sampleRate = Int(payload.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian })
                let bits = Int(payload.subdata(in: 14..<16).withUnsafeBytes { $0.load(as: UInt16.self).littleEndian })
                fmt = (channels, sampleRate, bits)
            case "data":
                dataInfo = (Int(payloadOffset), Int(size))
            case "bext":
                try handle.seek(toOffset: payloadOffset)
                if let payload = try? handle.read(upToCount: Int(size)) {
                    bextDescription = String(data: payload.subdata(in: 0..<min(256, payload.count)), encoding: .ascii)?
                        .trimmingCharacters(in: .controlCharacters)
                        .trimmingCharacters(in: .whitespaces)
                    if payload.count >= 330 {
                        bextOriginationDate = String(data: payload.subdata(in: 320..<min(330, payload.count)), encoding: .ascii)
                    }
                    if payload.count >= 338 {
                        bextOriginationTime = String(data: payload.subdata(in: 330..<min(338, payload.count)), encoding: .ascii)
                    }
                }
            case "iXML":
                try handle.seek(toOffset: payloadOffset)
                if let payload = try? handle.read(upToCount: Int(size)) {
                    ixmlContent = String(data: payload, encoding: .utf8)?
                        .trimmingCharacters(in: .controlCharacters)
                }
            default:
                break
            }

            offset = payloadOffset + UInt64(size) + (size % 2 == 1 ? 1 : 0)
        }

        guard let fmt else { throw WavReadError.missingFmtChunk }
        guard let dataInfo else { throw WavReadError.missingDataChunk }

        let bytesPerFrame = fmt.channels * (fmt.bitsPerSample / 8)
        let frameCount = bytesPerFrame == 0 ? 0 : dataInfo.size / bytesPerFrame
        let duration = Double(frameCount) / Double(fmt.sampleRate)

        return WavMetadata(
            channelCount: fmt.channels,
            sampleRate: fmt.sampleRate,
            bitsPerSample: fmt.bitsPerSample,
            frameCount: frameCount,
            durationSeconds: duration,
            dataChunkOffset: dataInfo.offset,
            dataChunkSize: dataInfo.size,
            bextDescription: bextDescription,
            bextOriginationDate: bextOriginationDate,
            bextOriginationTime: bextOriginationTime,
            ixmlContent: ixmlContent
        )
    }
}
