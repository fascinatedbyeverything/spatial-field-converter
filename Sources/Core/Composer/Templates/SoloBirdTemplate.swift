import Foundation

public struct SoloBirdTemplate: Template {
    public let id = "solo_bird"
    public let displayName = "Solo Bird"
    public init() {}

    public func schedule(set: SetData, durationSec: Double, seed: UInt64) -> [ObjectPlan] {
        var rng = SeededGenerator(seed: seed)
        let species = set.keptElements.filter { $0.kind == "species" }
        guard let featured = species.max(by: { $0.confidence < $1.confidence }) else { return [] }

        let featuredCount = Int(durationSec / 15.0)
        var plans: [ObjectPlan] = []

        let times = EventScheduler.uniform(count: featuredCount, durationSec: durationSec,
                                           jitter: 0.5, rng: &rng)
        for t in times {
            let pos = PositionAssigner.assign(label: featured.label, kind: "species",
                                              behavior: .discrete, rng: &rng)
            plans.append(ObjectPlan(
                label: featured.label, scientific: featured.scientific,
                sourceClipR2Key: sampleR2Key(for: featured),
                startSec: t, durationSec: featured.durationSec,
                positionCurve: [pos],
                volume: 1.0, loop: false,
                behavior: featured.behaviorHint, locked: false))
        }

        let others = species.filter { $0.label != featured.label }
        for el in others {
            let t = Double.random(in: 0...durationSec, using: &rng)
            let pos = PositionAssigner.assign(label: el.label, kind: "species",
                                              behavior: .discrete, rng: &rng)
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
