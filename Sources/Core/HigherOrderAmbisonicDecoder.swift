import Accelerate
import Foundation

public enum AmbisonicOrder: Int, Sendable, Equatable {
    case first = 1   // 4 channels (W,Y,Z,X)
    case second = 2  // 9 channels
    case third = 3   // 16 channels

    public var channelCount: Int { (rawValue + 1) * (rawValue + 1) }

    /// Returns the AmbisonicOrder matching the channel count, or nil if not a valid AmbiX layout.
    public static func fromChannelCount(_ count: Int) -> AmbisonicOrder? {
        switch count {
        case 4:  return .first
        case 9:  return .second
        case 16: return .third
        default: return nil
        }
    }
}

/// Decodes a higher-order B-format AmbiX signal (ACN/SN3D) onto a fixed loudspeaker layout
/// using the basic decoder with max-rE per-order weighting.
///
/// Reference: Zotter & Frank, "Ambisonics" (2019), Table 4.1 (max-rE weights),
/// and Politis HOA toolbox for the SN3D-normalized real spherical harmonic formulas.
///
/// Channel order (ACN, SN3D normalization):
///   n=0: [W]
///   n=1: [Y, Z, X]               (m = -1, 0, +1)
///   n=2: [V, T, R, S, U]         (m = -2, -1, 0, +1, +2)
///   n=3: [Q, O, M, K, L, N, P]   (m = -3, -2, -1, 0, +1, +2, +3)
///
/// AmbiX convention: azimuth=0 → front, azimuth=+π/2 → left; elevation=0 → horizontal.
public struct HigherOrderAmbisonicDecoder: Sendable {

    public let order: AmbisonicOrder
    public let speakerPositions: [SpeakerPosition]

    /// decodeMatrix[speaker][ambisonicChannel]
    private let decodeMatrix: [[Float]]
    /// Flattened row-major decode matrix for cblas_sgemm. Precomputed once at init.
    private let flatMatrix: [Float]   // speakerCount × channelCount in row-major order

    public init(order: AmbisonicOrder, speakerPositions: [SpeakerPosition]) {
        self.order = order
        self.speakerPositions = speakerPositions
        let dm = Self.buildDecodeMatrix(order: order, positions: speakerPositions)
        self.decodeMatrix = dm
        // Flatten row-major for cblas_sgemm
        var flat: [Float] = []
        flat.reserveCapacity(dm.count * order.channelCount)
        for row in dm {
            flat.append(contentsOf: row)
        }
        self.flatMatrix = flat
    }

    /// Decode one frame of B-format (ACN-ordered SN3D) to all speaker outputs.
    public func decode(ambisonicFrame: [Float]) -> [Float] {
        precondition(ambisonicFrame.count == order.channelCount,
                     "expected \(order.channelCount) channels for order \(order.rawValue), got \(ambisonicFrame.count)")
        var output = [Float](repeating: 0, count: speakerPositions.count)
        for s in 0..<speakerPositions.count {
            var sum: Float = 0
            let row = decodeMatrix[s]
            for c in 0..<order.channelCount {
                sum += row[c] * ambisonicFrame[c]
            }
            output[s] = sum
        }
        return output
    }

    /// Decode an interleaved buffer.
    ///
    /// Uses cblas_sgemm: C = A · B^T where A = input (N×K), B = flatMatrix (M×K).
    /// N = frameCount, K = order.channelCount, M = speakerPositions.count.
    public func decode(interleavedAmbisonic input: [Float], frameCount: Int) -> [Float] {
        let inCh = order.channelCount
        let outCh = speakerPositions.count
        precondition(input.count >= frameCount * inCh, "input buffer too small")
        var output = [Float](repeating: 0, count: frameCount * outCh)
        input.withUnsafeBufferPointer { aPtr in
            flatMatrix.withUnsafeBufferPointer { bPtr in
                output.withUnsafeMutableBufferPointer { cPtr in
                    cblas_sgemm(
                        CblasRowMajor,
                        CblasNoTrans,       // op(A) = A  (frameCount × inCh)
                        CblasTrans,         // op(B) = B^T (inCh × outCh)
                        Int32(frameCount),  // M: rows of C and op(A)
                        Int32(outCh),       // N: cols of C and op(B)
                        Int32(inCh),        // K: cols of op(A) / rows of op(B)
                        1.0,                // α
                        aPtr.baseAddress,
                        Int32(inCh),        // lda = K
                        bPtr.baseAddress,
                        Int32(inCh),        // ldb = K  (B is outCh×inCh row-major)
                        0.0,                // β
                        cPtr.baseAddress,
                        Int32(outCh)        // ldc = outCh
                    )
                }
            }
        }
        return output
    }

    // MARK: - Decoder construction

    private static func buildDecodeMatrix(order: AmbisonicOrder, positions: [SpeakerPosition]) -> [[Float]] {
        // max-rE per-order weights for 3D regular layouts.
        // Source: Zotter & Frank "Ambisonics" 2019, Table 4.1.
        // Index into this array by ACN channel index; each weight corresponds to degree n.
        let perOrderWeights: [Float]
        switch order {
        case .first:
            perOrderWeights = [0.7745966, 0.4472135, 0.4472135, 0.4472135]
        case .second:
            perOrderWeights = [0.861,
                               0.755, 0.755, 0.755,
                               0.521, 0.521, 0.521, 0.521, 0.521]
        case .third:
            perOrderWeights = [0.861,
                               0.755, 0.755, 0.755,
                               0.521, 0.521, 0.521, 0.521, 0.521,
                               0.207, 0.207, 0.207, 0.207, 0.207, 0.207, 0.207]
        }
        let safety: Float = 0.7   // headroom against constructive directional peaks

        var matrix: [[Float]] = []
        for pos in positions {
            if pos.isLFE {
                // LFE = scaled W only; low-pass applied in StreamingDecoder.
                var row = [Float](repeating: 0, count: order.channelCount)
                row[0] = 0.316   // -10 dB per BS.775
                matrix.append(row)
                continue
            }
            let az = pos.azimuthDegrees * .pi / 180
            let el = pos.elevationDegrees * .pi / 180
            let sh = sphericalHarmonics(azimuth: az, elevation: el, order: order)
            var row = [Float](repeating: 0, count: order.channelCount)
            for c in 0..<order.channelCount {
                row[c] = sh[c] * perOrderWeights[c] * safety
            }
            matrix.append(row)
        }
        return matrix
    }

    /// Real SN3D-normalized spherical harmonics in ACN order, evaluated at (az, el).
    /// AmbiX convention: az=0 front, az=+π/2 left; el=0 horizontal, el=+π/2 up.
    ///
    /// Formulas from: https://en.wikipedia.org/wiki/Ambisonic_data_exchange_formats#ACN
    /// and Zotter & Frank "Ambisonics" (2019).
    public static func sphericalHarmonics(azimuth az: Float, elevation el: Float, order: AmbisonicOrder) -> [Float] {
        let ca = cos(az), sa = sin(az)
        let ce = cos(el), se = sin(el)
        var sh: [Float] = []

        // n = 0  (ACN 0)
        sh.append(1.0)                                          // W

        // n = 1  (ACN 1..3)
        sh.append(sa * ce)                                      // Y  (m = -1)
        sh.append(se)                                           // Z  (m =  0)
        sh.append(ca * ce)                                      // X  (m = +1)
        if order == .first { return sh }

        // n = 2  (ACN 4..8)
        let sqrt3_2: Float = sqrt(3.0) / 2.0
        sh.append(sqrt3_2 * sin(2 * az) * ce * ce)             // V  (m = -2)
        sh.append(sqrt3_2 * sa * sin(2 * el))                  // T  (m = -1)
        sh.append((3 * se * se - 1) / 2)                       // R  (m =  0)
        sh.append(sqrt3_2 * ca * sin(2 * el))                  // S  (m = +1)
        sh.append(sqrt3_2 * cos(2 * az) * ce * ce)             // U  (m = +2)
        if order == .second { return sh }

        // n = 3  (ACN 9..15)
        let sqrt5_8: Float = sqrt(5.0 / 8.0)
        let sqrt15_2: Float = sqrt(15.0) / 2.0
        let sqrt3_8: Float = sqrt(3.0 / 8.0)
        sh.append(sqrt5_8 * sin(3 * az) * ce * ce * ce)        // Q  (m = -3)
        sh.append(sqrt15_2 * sin(2 * az) * se * ce * ce)       // O  (m = -2)
        sh.append(sqrt3_8 * sa * ce * (5 * se * se - 1))       // M  (m = -1)
        sh.append(se * (5 * se * se - 3) / 2)                  // K  (m =  0)
        sh.append(sqrt3_8 * ca * ce * (5 * se * se - 1))       // L  (m = +1)
        sh.append(sqrt15_2 * cos(2 * az) * se * ce * ce)       // N  (m = +2)
        sh.append(sqrt5_8 * cos(3 * az) * ce * ce * ce)        // P  (m = +3)
        return sh
    }
}

// MARK: - Streaming wrapper

public extension HigherOrderAmbisonicDecoder {

    /// Returns a stateful streaming decoder that applies an 80 Hz Butterworth low-pass
    /// to LFE channels (per ITU-R BS.775), mirroring VirtualLoudspeakerRig.StreamingDecoder.
    func makeStreamingDecoder(sampleRate: Int) -> StreamingDecoder {
        return StreamingDecoder(decoder: self, sampleRate: sampleRate)
    }

    /// Stateful HOA → loudspeaker decoder with LFE low-pass. Not thread-safe.
    final class StreamingDecoder {
        private let decoder: HigherOrderAmbisonicDecoder
        private let lfeFilter: BiquadLowpass
        private let lfeGain: Float = 0.316   // -10 dB per BS.775

        init(decoder: HigherOrderAmbisonicDecoder, sampleRate: Int) {
            self.decoder = decoder
            self.lfeFilter = BiquadLowpass(sampleRate: Float(sampleRate), cutoffHz: 80)
        }

        /// Decode, then replace each LFE channel with a low-passed W feed.
        public func process(interleavedAmbisonic input: [Float], frameCount: Int) -> [Float] {
            var output = decoder.decode(interleavedAmbisonic: input, frameCount: frameCount)
            let speakerCount = decoder.speakerPositions.count
            let inCh = decoder.order.channelCount
            for (i, pos) in decoder.speakerPositions.enumerated() where pos.isLFE {
                for f in 0..<frameCount {
                    let w = input[f * inCh + 0]
                    output[f * speakerCount + i] = lfeFilter.process(w) * lfeGain
                }
            }
            return output
        }
    }
}
