import Foundation

public struct PCMBlock {
    public let samples: [Float]
    public let frameCount: Int
    public let channelCount: Int
}

public final class WavSampleReader {
    private let handle: FileHandle
    private let metadata: WavMetadata
    private var framesRead: Int = 0

    public init(reader: WavFileReader) throws {
        self.metadata = reader.metadata
        self.handle = try FileHandle(forReadingFrom: reader.url)
        try handle.seek(toOffset: UInt64(metadata.dataChunkOffset))
    }

    deinit {
        try? handle.close()
    }

    public func readNextBlock(maxFrames: Int) throws -> PCMBlock? {
        let remaining = metadata.frameCount - framesRead
        guard remaining > 0 else { return nil }
        let framesToRead = min(maxFrames, remaining)

        let bytesPerSample = metadata.bitsPerSample / 8
        let bytesToRead = framesToRead * metadata.channelCount * bytesPerSample
        guard let raw = try handle.read(upToCount: bytesToRead), raw.count == bytesToRead else {
            return nil
        }

        let totalSamples = framesToRead * metadata.channelCount
        var floats = [Float](repeating: 0, count: totalSamples)

        switch metadata.bitsPerSample {
        case 16:
            raw.withUnsafeBytes { ptr in
                let i16 = ptr.bindMemory(to: Int16.self)
                for i in 0..<totalSamples {
                    floats[i] = Float(Int16(littleEndian: i16[i])) / Float(Int16.max)
                }
            }
        case 24:
            raw.withUnsafeBytes { ptr in
                let bytes = ptr.bindMemory(to: UInt8.self)
                for i in 0..<totalSamples {
                    let b0 = Int32(bytes[i * 3])
                    let b1 = Int32(bytes[i * 3 + 1])
                    let b2 = Int32(bytes[i * 3 + 2])
                    var v = (b2 << 16) | (b1 << 8) | b0
                    if v & 0x800000 != 0 { v |= -0x1000000 }
                    floats[i] = Float(v) / Float(0x800000)
                }
            }
        case 32:
            raw.withUnsafeBytes { ptr in
                let i32 = ptr.bindMemory(to: Int32.self)
                for i in 0..<totalSamples {
                    floats[i] = Float(Int32(littleEndian: i32[i])) / Float(Int32.max)
                }
            }
        default:
            return nil
        }

        framesRead += framesToRead
        return PCMBlock(samples: floats, frameCount: framesToRead, channelCount: metadata.channelCount)
    }
}
