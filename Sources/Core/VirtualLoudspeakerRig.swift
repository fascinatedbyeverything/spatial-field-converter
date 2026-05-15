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

    public init(speakerPositions: [SpeakerPosition]) {
        self.speakerPositions = speakerPositions
        self.decodeMatrix = Self.buildDecodeMatrix(positions: speakerPositions)
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
    public func decode(interleavedBformat input: [Float], frameCount: Int) -> [Float] {
        let speakerCount = speakerPositions.count
        var output = [Float](repeating: 0, count: frameCount * speakerCount)
        for f in 0..<frameCount {
            let frame = Array(input[(f * 4)..<((f + 1) * 4)])
            let speakers = decode(bformatFrame: frame)
            for s in 0..<speakerCount {
                output[f * speakerCount + s] = speakers[s]
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
            // Basic decoder: speaker_i = (W*wW + Y*wY*dirY + Z*wZ*dirZ + X*wX*dirX) / N
            matrix.append([
                wW / nonLFECount,
                Float(wY * dirY) / nonLFECount,
                Float(wZ * dirZ) / nonLFECount,
                Float(wX * dirX) / nonLFECount
            ])
        }
        return matrix
    }
}
