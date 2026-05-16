import Accelerate
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

    /// Flattened row-major decode matrix for cblas_sgemm. Precomputed once at init.
    private let flatMatrix: [Float]

    public init(matrix: [[Float]]) {
        precondition(!matrix.isEmpty, "matrix must not be empty")
        precondition(matrix.allSatisfy { $0.count == matrix[0].count }, "matrix must be rectangular")
        self.matrix = matrix
        self.outputChannelCount = matrix.count
        self.inputChannelCount = matrix[0].count
        // Flatten row-major for cblas_sgemm: flatMatrix[r*inCh + c] = matrix[r][c]
        var flat: [Float] = []
        flat.reserveCapacity(matrix.count * matrix[0].count)
        for row in matrix {
            flat.append(contentsOf: row)
        }
        self.flatMatrix = flat
    }

    /// Decode an interleaved input buffer. Returns interleaved output with `frameCount`
    /// frames and `outputChannelCount` channels.
    ///
    /// Uses cblas_sgemm: C = A · B^T where A = input (N×K), B = flatMatrix (M×K).
    /// N = frameCount, K = inputChannelCount, M = outputChannelCount.
    public func decode(interleavedAFormat input: [Float], frameCount: Int) -> [Float] {
        precondition(input.count >= frameCount * inputChannelCount, "input buffer too small")
        var output = [Float](repeating: 0, count: frameCount * outputChannelCount)
        input.withUnsafeBufferPointer { aPtr in
            flatMatrix.withUnsafeBufferPointer { bPtr in
                output.withUnsafeMutableBufferPointer { cPtr in
                    cblas_sgemm(
                        CblasRowMajor,
                        CblasNoTrans,               // op(A) = A  (N×K)
                        CblasTrans,                 // op(B) = B^T (K×M)
                        Int32(frameCount),          // M: rows of C and op(A)
                        Int32(outputChannelCount),  // N: cols of C and op(B)
                        Int32(inputChannelCount),   // K: cols of op(A) / rows of op(B)
                        1.0,                        // α
                        aPtr.baseAddress,
                        Int32(inputChannelCount),   // lda = K
                        bPtr.baseAddress,
                        Int32(inputChannelCount),   // ldb = K  (B is M×K row-major)
                        0.0,                        // β
                        cPtr.baseAddress,
                        Int32(outputChannelCount)   // ldc = M
                    )
                }
            }
        }
        return output
    }
}
