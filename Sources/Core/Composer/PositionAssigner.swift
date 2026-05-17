import Foundation

/// Picks a 3D position for a sound based on its category + behavior.
/// Seed-driven for deterministic re-rolls.
public enum PositionAssigner {

    public static func assign<RNG: RandomNumberGenerator>(
        label: String, kind: String, behavior: BehaviorHint, rng: inout RNG
    ) -> PositionKeyframe {
        let band = yBand(label: label, kind: kind, behavior: behavior)
        let x = Float.random(in: -1.0...1.0, using: &rng)
        let y = Float.random(in: band.lower...band.upper, using: &rng)
        let z = Float.random(in: -1.0...1.0, using: &rng)
        return PositionKeyframe(timeSec: 0, x: x, y: y, z: z)
    }

    public static func flybyCurve<RNG: RandomNumberGenerator>(
        label: String, durationSec: Double, rng: inout RNG
    ) -> [PositionKeyframe] {
        let band = yBand(label: label, kind: "species", behavior: .flyby)
        let y = Float.random(in: band.lower...band.upper, using: &rng)
        let zMid = Float.random(in: -0.6...0.6, using: &rng)
        let leftToRight = Bool.random(using: &rng)
        let xStart: Float = leftToRight ? -0.9 : 0.9
        let xEnd: Float   = leftToRight ?  0.9 : -0.9
        return [
            PositionKeyframe(timeSec: 0, x: xStart, y: y, z: zMid + 0.2),
            PositionKeyframe(timeSec: durationSec * 0.5, x: 0, y: y, z: zMid),
            PositionKeyframe(timeSec: durationSec, x: xEnd, y: y, z: zMid - 0.2)
        ]
    }

    private static func yBand(label: String, kind: String, behavior: BehaviorHint)
        -> (lower: Float, upper: Float) {
        let lower = label.lowercased()
        if kind == "species" {
            if lower.contains("mammal") || lower.contains("dog") || lower.contains("cat")
                || lower.contains("squirrel") || lower.contains("howler") {
                return (-0.3, 0.1)
            }
            return (0.4, 0.9)
        }
        if lower.contains("water") || lower.contains("rain") || lower.contains("ocean") {
            return (-0.2, 0.2)
        }
        if lower.contains("wind") {
            return (0.0, 0.4)
        }
        if lower.contains("insect") || lower.contains("cricket") {
            return (-0.2, 0.2)
        }
        if lower.contains("vehicle") || lower.contains("car") || lower.contains("horn") {
            return (-0.1, 0.3)
        }
        if lower.contains("voice") || lower.contains("speech") {
            return (-0.1, 0.3)
        }
        return (-0.5, 0.9)
    }
}

/// Deterministic xorshift64 generator for reproducible composition.
public struct SeededGenerator: RandomNumberGenerator {
    public var state: UInt64
    public init(seed: UInt64) {
        self.state = seed == 0 ? 0xdeadbeefdeadbeef : seed
    }
    public mutating func next() -> UInt64 {
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        return state &* 0x2545F4914F6CDD1D
    }
}
