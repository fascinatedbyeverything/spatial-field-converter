import Foundation
import AVFoundation

public enum BedEncoderError: Error {
    case writerFailed(String)
    case appendFailed
}

/// Encodes interleaved 10-channel float-32 PCM into an `.m4a` container with the
/// `kAudioChannelLayoutTag_Atmos_7_1_2` channel layout (L R C LFE Ls Rs Rls Rrs Ltm Rtm).
///
/// The audio is stored as 32-bit float LPCM rather than AAC-LC because macOS's built-in
/// AAC encoder does not support more than 8 channels. For v0.1 this is an acceptable
/// trade-off: the channel layout metadata is correctly declared, and the file is
/// re-openable by AVFoundation with `mChannelsPerFrame == 10`.
///
/// Usage: instantiate → call `appendFrames` repeatedly → `try await finalize()`.
///
/// Not thread-safe.
public final class BedEncoder {
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let format: AVAudioFormat
    private var framesAppended: Int64 = 0
    private let sampleRate: Int

    public init(outputURL: URL, sampleRate: Int) throws {
        self.sampleRate = sampleRate
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        self.writer = try AVAssetWriter(outputURL: outputURL, fileType: .m4a)

        var layoutStruct = AudioChannelLayout()
        layoutStruct.mChannelLayoutTag = kAudioChannelLayoutTag_Atmos_7_1_2
        let layoutData = Data(bytes: &layoutStruct, count: MemoryLayout<AudioChannelLayout>.size)

        // LPCM in m4a — macOS AAC encoder does not support > 8 channels.
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVNumberOfChannelsKey: 10,
            AVSampleRateKey: sampleRate,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVChannelLayoutKey: layoutData,
        ]

        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: outputSettings)
        input.expectsMediaDataInRealTime = false

        guard writer.canAdd(input) else {
            throw BedEncoderError.writerFailed("cannot add audio input")
        }
        writer.add(input)
        self.input = input

        // AVAudioFormat via AVAudioChannelLayout — required for > 8 ch interleaved LPCM.
        guard let avLayout = AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_Atmos_7_1_2) else {
            throw BedEncoderError.writerFailed("cannot create AVAudioChannelLayout for Atmos_7_1_2")
        }
        self.format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(sampleRate),
            interleaved: true,
            channelLayout: avLayout
        )

        guard writer.startWriting() else {
            throw BedEncoderError.writerFailed("startWriting returned false: \(writer.error?.localizedDescription ?? "")")
        }
        writer.startSession(atSourceTime: .zero)
    }

    public func appendFrames(_ samples: [Float], frameCount: Int) throws {
        let channelCount = 10
        precondition(samples.count >= frameCount * channelCount, "buffer too small")

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else {
            throw BedEncoderError.appendFailed
        }
        buffer.frameLength = AVAudioFrameCount(frameCount)

        // Interleaved: single mBuffers entry holds all channel data.
        if let dataPtr = buffer.audioBufferList.pointee.mBuffers.mData?.assumingMemoryBound(to: Float.self) {
            for i in 0..<(frameCount * channelCount) {
                dataPtr[i] = samples[i]
            }
        }

        let sampleBuffer = try makeSampleBuffer(from: buffer, presentationTimeFrame: framesAppended)

        while !input.isReadyForMoreMediaData {
            Thread.sleep(forTimeInterval: 0.005)
        }
        guard input.append(sampleBuffer) else {
            throw BedEncoderError.appendFailed
        }
        framesAppended += Int64(frameCount)
    }

    public func finalize() async throws {
        input.markAsFinished()
        await writer.finishWriting()
        if writer.status == .failed {
            throw BedEncoderError.writerFailed(writer.error?.localizedDescription ?? "unknown")
        }
    }

    private func makeSampleBuffer(from pcmBuffer: AVAudioPCMBuffer, presentationTimeFrame: Int64) throws -> CMSampleBuffer {
        let timescale = Int32(self.sampleRate)

        var asbdForDesc = format.streamDescription.pointee
        var layoutStruct = AudioChannelLayout()
        layoutStruct.mChannelLayoutTag = kAudioChannelLayoutTag_Atmos_7_1_2

        var formatDescription: CMFormatDescription?
        let fmtStatus = CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &asbdForDesc,
            layoutSize: MemoryLayout<AudioChannelLayout>.size,
            layout: &layoutStruct,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDescription
        )
        guard fmtStatus == noErr, let formatDescription else {
            throw BedEncoderError.writerFailed("CMAudioFormatDescriptionCreate failed: \(fmtStatus)")
        }

        var sampleBuffer: CMSampleBuffer?
        let pts = CMTime(value: presentationTimeFrame, timescale: timescale)
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: timescale),
            presentationTimeStamp: pts,
            decodeTimeStamp: .invalid
        )

        let createStatus = CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: nil,
            dataReady: false,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDescription,
            sampleCount: CMItemCount(pcmBuffer.frameLength),
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        )
        guard createStatus == noErr, let sampleBuffer else {
            throw BedEncoderError.writerFailed("CMSampleBufferCreate failed: \(createStatus)")
        }

        let setStatus = CMSampleBufferSetDataBufferFromAudioBufferList(
            sampleBuffer,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: 0,
            bufferList: pcmBuffer.audioBufferList
        )
        guard setStatus == noErr else {
            throw BedEncoderError.writerFailed("SetDataBufferFromAudioBufferList failed: \(setStatus)")
        }

        return sampleBuffer
    }
}
