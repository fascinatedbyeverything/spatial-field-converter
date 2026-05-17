import Foundation

public struct DawnChorusTemplate: Template {
    public let id = "dawn_chorus"
    public let displayName = "Dawn Chorus"
    public init() {}

    public func schedule(set: SetData, durationSec: Double, seed: UInt64) -> [ObjectPlan] {
        var rng = SeededGenerator(seed: seed)
        let kept = set.keptElements.filter { $0.behaviorHint != .sustained }
        guard !kept.isEmpty else { return [] }

        let species = kept.filter { $0.kind == "species" }
        let others = kept.filter { $0.kind != "species" }
        let totalEvents = max(8, Int(durationSec / 10.0))
        let speciesEvents = Int(Double(totalEvents) * 0.7)
        let otherEvents = totalEvents - speciesEvents

        var plans: [ObjectPlan] = []

        for _ in 0..<speciesEvents {
            guard let el = species.randomElement(using: &rng) else { break }
            let times = EventScheduler.rampIn(count: 1, durationSec: durationSec, rng: &rng)
            let pos = PositionAssigner.assign(label: el.label, kind: el.kind,
                                              behavior: el.behaviorHint, rng: &rng)
            plans.append(ObjectPlan(
                label: el.label, scientific: el.scientific,
                sourceClipR2Key: sampleR2Key(for: el),
                startSec: times[0], durationSec: el.durationSec,
                positionCurve: [pos],
                volume: 1.0, loop: false,
                behavior: el.behaviorHint, locked: false))
        }
        for _ in 0..<otherEvents {
            guard let el = others.randomElement(using: &rng) else { break }
            let times = EventScheduler.sparseRandom(count: 1, durationSec: durationSec, rng: &rng)
            let pos = PositionAssigner.assign(label: el.label, kind: el.kind,
                                              behavior: el.behaviorHint, rng: &rng)
            plans.append(ObjectPlan(
                label: el.label, scientific: el.scientific,
                sourceClipR2Key: sampleR2Key(for: el),
                startSec: times[0], durationSec: el.durationSec,
                positionCurve: [pos],
                volume: 0.7, loop: false,
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
