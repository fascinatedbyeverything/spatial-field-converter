import Accelerate
import Foundation

public struct SpeakerPosition: Sendable, Equatable {
    public let name: String
    public let azimuthDegrees: Float    // 0 = front, +90 = left, -90 = right (AmbiX convention)
    public let elevationDegrees: Float  // 0 = horizontal, +90 = up
    public let isLFE: Bool
}

/// Decodes a 1st-order B-format AmbiX frame (W, Y, Z, X) onto a fixed loudspeaker layout.
///
/// Uses the basic decoder with max-rE weighting (Zotter & Frank, "Ambisonics" 2019, Table 4.1)
/// for 1st-order — sharpens directional localization vs. naive in-phase decoding.
///
/// LFE channels receive an unfiltered scaled contribution at single-frame granularity;
/// the streaming wrapper (`makeStreamingDecoder`) applies a Butterworth low-pass at 80 Hz
/// per BS.775.
///
/// Not thread-safe across mutating streaming decoders; the rig itself is `Sendable`.
public struct VirtualLoudspeakerRig: Sendable {

    public let speakerPositions: [SpeakerPosition]
    public var speakerNames: [String] { speakerPositions.map { $0.name } }

    private let decodeMatrix: [[Float]]   // [speaker][bformatChannel: W,Y,Z,X]
    /// Flattened row-major decode matrix for cblas_sgemm. Precomputed once at init.
    private let flatMatrix: [Float]       // speaker × 4 in row-major order

    public init(speakerPositions: [SpeakerPosition]) {
        self.speakerPositions = speakerPositions
        let dm = Self.buildDecodeMatrix(positions: speakerPositions)
        self.decodeMatrix = dm
        // Flatten row-major for cblas_sgemm
        var flat: [Float] = []
        flat.reserveCapacity(dm.count * 4)
        for row in dm {
            flat.append(contentsOf: row)
        }
        self.flatMatrix = flat
    }

    /// Atmos bed channel order: L, R, C, LFE, Lss, Rss, Lrs, Rrs, Ltf, Rtf
    public static func atmos7_1_2() -> VirtualLoudspeakerRig {
        return VirtualLoudspeakerRig(speakerPositions: [
            SpeakerPosition(name: "L",   azimuthDegrees:  30, elevationDegrees:  0, isLFE: false),
            SpeakerPosition(name: "R",   azimuthDegrees: -30, elevationDegrees:  0, isLFE: false),
            SpeakerPosition(name: "C",   azimuthDegrees:   0, elevationDegrees:  0, isLFE: false),
            SpeakerPosition(name: "LFE", azimuthDegrees:   0, elevationDegrees:  0, isLFE: true),
            SpeakerPosition(name: "Lss", azimuthDegrees:  90, elevationDegrees:  0, isLFE: false),
            SpeakerPosition(name: "Rss", azimuthDegrees: -90, elevationDegrees:  0, isLFE: false),
            SpeakerPosition(name: "Lrs", azimuthDegrees: 135, elevationDegrees:  0, isLFE: false),
            SpeakerPosition(name: "Rrs", azimuthDegrees:-135, elevationDegrees:  0, isLFE: false),
            SpeakerPosition(name: "Ltf", azimuthDegrees:  45, elevationDegrees: 45, isLFE: false),
            SpeakerPosition(name: "Rtf", azimuthDegrees: -45, elevationDegrees: 45, isLFE: false),
        ])
    }

    /// Decode one frame of B-format (W, Y, Z, X in AmbiX/ACN order) to all speaker outputs.
    public func decode(bformatFrame: [Float]) -> [Float] {
        precondition(bformatFrame.count == 4, "1st-order B-format requires 4 channels (W,Y,Z,X)")
        var output = [Float](repeating: 0, count: speakerPositions.count)
        for i in 0..<speakerPositions.count {
            var sum: Float = 0
            for c in 0..<4 {
                sum += decodeMatrix[i][c] * bformatFrame[c]
            }
            output[i] = sum
        }
        return output
    }

    /// Decode an interleaved B-format buffer into an interleaved N-speaker buffer.
    ///
    /// Uses cblas_sgemm: C = A · B^T where A = input (N×4), B = flatMatrix (M×4).
    /// N = frameCount, K = 4 (B-format channels), M = speakerCount.
    public func decode(interleavedBformat input: [Float], frameCount: Int) -> [Float] {
        let speakerCount = speakerPositions.count
        let bformatChannels = 4
        var output = [Float](repeating: 0, count: frameCount * speakerCount)
        input.withUnsafeBufferPointer { aPtr in
            flatMatrix.withUnsafeBufferPointer { bPtr in
                output.withUnsafeMutableBufferPointer { cPtr in
                    cblas_sgemm(
                        CblasRowMajor,
                        CblasNoTrans,               // op(A) = A  (frameCount × 4)
                        CblasTrans,                 // op(B) = B^T (4 × speakerCount)
                        Int32(frameCount),          // M: rows of C and op(A)
                        Int32(speakerCount),        // N: cols of C and op(B)
                        Int32(bformatChannels),     // K: cols of op(A) / rows of op(B)
                        1.0,                        // α
                        aPtr.baseAddress,
                        Int32(bformatChannels),     // lda = K
                        bPtr.baseAddress,
                        Int32(bformatChannels),     // ldb = K  (B is speakerCount×4 row-major)
                        0.0,                        // β
                        cPtr.baseAddress,
                        Int32(speakerCount)         // ldc = speakerCount
                    )
                }
            }
        }
        return output
    }

    /// Build per-speaker decode coefficients using a 1st-order basic decoder
    /// with max-rE weighting. References: Daniel 2000; Zotter & Frank 2019.
    private static func buildDecodeMatrix(positions: [SpeakerPosition]) -> [[Float]] {
        // 1st-order max-rE weights — Zotter & Frank, "Ambisonics" (2019), Table 4.1
        let wW: Float = 0.7745966692
        let wY: Float = 0.4472135955
        let wZ: Float = 0.4472135955
        let wX: Float = 0.4472135955

        let nonLFECount = Float(positions.filter { !$0.isLFE }.count)
        var matrix: [[Float]] = []

        for pos in positions {
            if pos.isLFE {
                // LFE single-frame contribution: scaled W. Low-pass applied in StreamingDecoder.
                // BS.775 LFE level relative to main is -10 dB ≈ 0.316.
                matrix.append([0.316, 0, 0, 0])
                continue
            }
            let azRad = pos.azimuthDegrees * .pi / 180
            let elRad = pos.elevationDegrees * .pi / 180
            // AmbiX direction: X = cos(el)*cos(az), Y = cos(el)*sin(az), Z = sin(el)
            let dirX = cos(elRad) * cos(azRad)
            let dirY = cos(elRad) * sin(azRad)
            let dirZ = sin(elRad)
            // Basic decoder: speaker_i = W*wW + Y*wY*dirY + Z*wZ*dirZ + X*wX*dirX
            //
            // The classic ambisonic decoder divides each speaker by N (number of speakers)
            // for amplitude preservation under simultaneous playback through N physical
            // speakers. That's correct for room speakers. It is WRONG for our pipeline,
            // where each bed/object channel is auditioned (or re-rendered by Atmos
            // Renderer) in isolation: dividing by 9 leaves quiet ambience ~19 dB below
            // audibility while preserving loud transients. Removed.
            //
            // The max-rE spherical-harmonic weights (wW = sqrt(3/5), wXYZ = sqrt(1/5))
            // already supply the correct relative normalization between W and the
            // directional channels. A small overall safety gain (0.7) leaves headroom
            // for the worst-case constructive direction (peak ≈ 1.22 unscaled).
            let safety: Float = 0.7
            matrix.append([
                wW * safety,
                Float(wY * dirY) * safety,
                Float(wZ * dirZ) * safety,
                Float(wX * dirX) * safety
            ])
        }
        return matrix
    }
}

public extension VirtualLoudspeakerRig {

    /// Returns a stateful streaming decoder that applies a 2nd-order Butterworth low-pass
    /// at 80 Hz to LFE channels (per ITU-R BS.775 conventions).
    func makeStreamingDecoder(sampleRate: Int) -> StreamingDecoder {
        return StreamingDecoder(rig: self, sampleRate: sampleRate)
    }

    /// Stateful B-format → loudspeaker decoder. Holds biquad state for LFE filtering across
    /// calls to `process`. Not thread-safe.
    final class StreamingDecoder {
        private let rig: VirtualLoudspeakerRig
        private let lfeFilter: BiquadLowpass
        private let lfeGain: Float = 0.316  // -10 dB per BS.775

        init(rig: VirtualLoudspeakerRig, sampleRate: Int) {
            self.rig = rig
            self.lfeFilter = BiquadLowpass(sampleRate: Float(sampleRate), cutoffHz: 80)
        }

        /// Decode and apply LFE low-pass. Returns interleaved 10-channel output.
        public func process(interleavedBformat input: [Float], frameCount: Int) -> [Float] {
            var output = rig.decode(interleavedBformat: input, frameCount: frameCount)
            let speakerCount = rig.speakerPositions.count
            for (i, pos) in rig.speakerPositions.enumerated() where pos.isLFE {
                for f in 0..<frameCount {
                    let w = input[f * 4 + 0]
                    output[f * speakerCount + i] = lfeFilter.process(w) * lfeGain
                }
            }
            return output
        }
    }
}

/// Direct-form-II transposed 2nd-order Butterworth low-pass biquad.
/// Stateful — instantiate one per audio stream.
final class BiquadLowpass {
    private let b0: Float
    private let b1: Float
    private let b2: Float
    private let a1: Float
    private let a2: Float
    private var z1: Float = 0
    private var z2: Float = 0

    init(sampleRate: Float, cutoffHz: Float) {
        let omega = 2 * Float.pi * cutoffHz / sampleRate
        let cosOmega = cos(omega)
        let sinOmega = sin(omega)
        let q: Float = 0.7071067811   // Butterworth Q
        let alpha = sinOmega / (2 * q)

        let a0 = 1 + alpha
        b0 = ((1 - cosOmega) / 2) / a0
        b1 = (1 - cosOmega) / a0
        b2 = ((1 - cosOmega) / 2) / a0
        a1 = (-2 * cosOmega) / a0
        a2 = (1 - alpha) / a0
    }

    @inlinable
    func process(_ x: Float) -> Float {
        let y = b0 * x + z1
        z1 = b1 * x - a1 * y + z2
        z2 = b2 * x - a2 * y
        return y
    }
}
