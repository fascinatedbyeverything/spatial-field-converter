import Foundation

public enum EventScheduler {

    public static func uniform<RNG: RandomNumberGenerator>(
        count: Int, durationSec: Double, jitter: Double, rng: inout RNG
    ) -> [Double] {
        guard count > 0 else { return [] }
        if count == 1 { return [durationSec / 2.0] }
        let slot = durationSec / Double(count - 1)
        return (0..<count).map { i in
            let base = Double(i) * slot
            if jitter <= 0 { return base }
            let offset = Double.random(in: -slot * jitter / 2.0 ... slot * jitter / 2.0, using: &rng)
            return max(0, min(durationSec, base + offset))
        }
    }

    public static func rampIn<RNG: RandomNumberGenerator>(
        count: Int, durationSec: Double, rng: inout RNG
    ) -> [Double] {
        guard count > 0 else { return [] }
        return (0..<count).map { _ in
            let u = sqrt(Double.random(in: 0.0...1.0, using: &rng))
            return u * durationSec
        }
    }

    public static func rampOut<RNG: RandomNumberGenerator>(
        count: Int, durationSec: Double, rng: inout RNG
    ) -> [Double] {
        guard count > 0 else { return [] }
        return (0..<count).map { _ in
            let u = 1.0 - sqrt(Double.random(in: 0.0...1.0, using: &rng))
            return u * durationSec
        }
    }

    public static func sparseRandom<RNG: RandomNumberGenerator>(
        count: Int, durationSec: Double, rng: inout RNG
    ) -> [Double] {
        return (0..<count).map { _ in Double.random(in: 0.0...durationSec, using: &rng) }
    }

    public static func gaussian<RNG: RandomNumberGenerator>(
        count: Int, durationSec: Double, stdDevFraction: Double, rng: inout RNG
    ) -> [Double] {
        let sigma = durationSec * stdDevFraction
        let mu = durationSec / 2.0
        return (0..<count).map { _ in
            let u1 = Double.random(in: 0.000001...1.0, using: &rng)
            let u2 = Double.random(in: 0.0...1.0, using: &rng)
            let z = sqrt(-2.0 * log(u1)) * cos(2.0 * .pi * u2)
            let t = mu + z * sigma
            return max(0, min(durationSec, t))
        }
    }
}
