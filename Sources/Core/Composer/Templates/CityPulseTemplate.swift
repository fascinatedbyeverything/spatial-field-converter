import Foundation

public struct CityPulseTemplate: Template {
    public let id = "city_pulse"
    public let displayName = "City Pulse"
    public init() {}

    public func schedule(set: SetData, durationSec: Double, seed: UInt64) -> [ObjectPlan] {
        var rng = SeededGenerator(seed: seed)
        let kept = set.keptElements.filter { $0.behaviorHint != .sustained }
        guard !kept.isEmpty else { return [] }

        let transients = kept.filter { $0.behaviorHint == .oneShot }
        let nature = kept.filter { $0.behaviorHint != .oneShot }
        let totalEvents = max(8, Int(durationSec / 8.0))
        let transientEvents = Int(Double(totalEvents) * 0.7)
        let natureEvents = totalEvents - transientEvents

        var plans: [ObjectPlan] = []

        for _ in 0..<transientEvents {
            guard let el = transients.randomElement(using: &rng) else { break }
            let t = Double.random(in: 0...durationSec, using: &rng)
            let pos = PositionAssigner.assign(label: el.label, kind: el.kind,
                                              behavior: el.behaviorHint, rng: &rng)
            plans.append(ObjectPlan(
                label: el.label, scientific: el.scientific,
                sourceClipR2Key: sampleR2Key(for: el),
                startSec: t, durationSec: el.durationSec,
                positionCurve: [pos],
                volume: 0.9, loop: false,
                behavior: el.behaviorHint, locked: false))
        }
        for _ in 0..<natureEvents {
            guard let el = nature.randomElement(using: &rng) else { break }
            let t = Double.random(in: 0...durationSec, using: &rng)
            let pos = PositionAssigner.assign(label: el.label, kind: el.kind,
                                              behavior: el.behaviorHint, rng: &rng)
            plans.append(ObjectPlan(
                label: el.label, scientific: el.scientific,
                sourceClipR2Key: sampleR2Key(for: el),
                startSec: t, durationSec: el.durationSec,
                positionCurve: [pos],
                volume: 0.5, loop: false,
                behavior: el.behaviorHint, locked: false))
        }
        if plans.count > 118 { plans = Array(plans.prefix(118)) }
        return plans
    }

    private func sampleR2Key(for el: SetData.Element) -> String {
        let speciesSlug = SetData.slugify(el.label)
        let confPct = Int(el.confidence * 100)
        let tStart = Int(el.timeSec)
        let filename = "\(speciesSlug)__\(el.sourceSlug)__t\(tStart)s__c\(String(format: "%03d", confPct)).m4a"
        return "samples/birds/\(speciesSlug)/\(filename)"
    }
}
