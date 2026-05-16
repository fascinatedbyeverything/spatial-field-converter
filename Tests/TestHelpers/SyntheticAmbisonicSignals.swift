import Foundation
@testable import SpatialFieldConverter

enum SyntheticAmbisonicSignals {

    /// Generate A-format VRH-8 samples representing a unit-amplitude impulse from a given direction.
    /// Direction vector is a unit XYZ vector in AmbiX coordinates (X=front, Y=left, Z=up).
    /// Producing A-format such that decoding via `VRH8DecoderMatrix.matrix` yields the expected
    /// (W, Y, Z, X) for that direction.
    static func aFormatImpulse(directionX: Float, directionY: Float, directionZ: Float, frameCount: Int) -> [Float] {
        // Target B-format at the impulse instant:
        let w: Float = 1.0 / sqrt(2.0)
        let x = directionX
        let y = directionY
        let z = directionZ

        // The VRH-8 forward matrix M is orthogonal up to scaling — the inverse mapping
        // from B-format back to A-format uses the same coefficient signs:
        let inv: [[Float]] = [
            [ 0.5,  0.5,  0.5,  0.5],   // FLU
            [ 0.5, -0.5,  0.5, -0.5],   // FRD
            [ 0.5,  0.5, -0.5, -0.5],   // BLD
            [ 0.5, -0.5, -0.5,  0.5],   // BRU
        ]

        let bformat: [Float] = [w, y, z, x]
        var aformat = [Float](repeating: 0, count: 4)
        for outCh in 0..<4 {
            for inCh in 0..<4 {
                aformat[outCh] += inv[outCh][inCh] * bformat[inCh]
            }
        }

        // Single impulse at frame 0 across all 4 channels (interleaved)
        var out = [Float](repeating: 0, count: frameCount * 4)
        for ch in 0..<4 {
            out[0 * 4 + ch] = aformat[ch]
        }
        return out
    }

    /// White-noise A-format (random) — for throughput / energy-conservation tests.
    static func aFormatNoise(frameCount: Int, seed: UInt64 = 42) -> [Float] {
        var generator = SeededGenerator(seed: seed)
        return (0..<(frameCount * 4)).map { _ in
            Float.random(in: -0.5...0.5, using: &generator)
        }
    }

    /// All-zero A-format buffer.
    static func aFormatZero(frameCount: Int) -> [Float] {
        return [Float](repeating: 0, count: frameCount * 4)
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { self.state = seed == 0 ? 1 : seed }
    mutating func next() -> UInt64 {
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        return state &* 0x2545F4914F6CDD1D
    }
}
