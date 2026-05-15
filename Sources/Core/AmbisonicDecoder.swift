import Foundation

/// Applies a fixed linear decode matrix to an interleaved multi-channel input buffer,
/// producing an interleaved multi-channel output buffer.
///
/// Used for ambisonic A-format → B-format conversion (and other channel-domain
/// linear transforms). The matrix is `[outChannel][inChannel]` — one row per output
/// channel, one coefficient per input channel.
///
/// Thread safety: the struct holds only `let` values and is safe to share across threads.
public struct AmbisonicDecoder: Sendable {
    public let matrix: [[Float]]
    public let outputChannelCount: Int
    public let inputChannelCount: Int

    public init(matrix: [[Float]]) {
        precondition(!matrix.isEmpty, "matrix must not be empty")
        precondition(matrix.allSatisfy { $0.count == matrix[0].count }, "matrix must be rectangular")
        self.matrix = matrix
        self.outputChannelCount = matrix.count
        self.inputChannelCount = matrix[0].count
    }

    /// Decode an interleaved input buffer. Returns interleaved output with `frameCount`
    /// frames and `outputChannelCount` channels.
    public func decode(interleavedAFormat input: [Float], frameCount: Int) -> [Float] {
        precondition(input.count >= frameCount * inputChannelCount, "input buffer too small")
        var output = [Float](repeating: 0, count: frameCount * outputChannelCount)
        for f in 0..<frameCount {
            for outCh in 0..<outputChannelCount {
                var sum: Float = 0
                let row = matrix[outCh]
                for inCh in 0..<inputChannelCount {
                    sum += row[inCh] * input[f * inputChannelCount + inCh]
                }
                output[f * outputChannelCount + outCh] = sum
            }
        }
        return output
    }
}
