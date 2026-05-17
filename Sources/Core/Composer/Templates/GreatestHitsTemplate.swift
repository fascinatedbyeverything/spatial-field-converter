import Foundation

public struct GreatestHitsTemplate: Template {
    public let id = "greatest_hits"
    public let displayName = "Greatest Hits"

    public init() {}

    public func schedule(set: SetData, durationSec: Double, seed: UInt64) -> [ObjectPlan] {
        var rng = SeededGenerator(seed: seed)
        let kept = set.keptElements.filter { $0.behaviorHint != .sustained }
        guard !kept.isEmpty else { return [] }

        let countPerElement = max(2, min(4, Int(durationSec / 60.0)))
        var allPlans: [ObjectPlan] = []

        // Group by label so we sample times per-species
        let byLabel = Dictionary(grouping: kept, by: { $0.label })
        for (_, elements) in byLabel {
            let best = elements.max(by: { $0.confidence < $1.confidence })!
            let times = EventScheduler.uniform(
                count: countPerElement,
                durationSec: durationSec,
                jitter: 0.4,
                rng: &rng
            )
            for t in times {
                let pos = PositionAssigner.assign(
                    label: best.label, kind: best.kind,
                    behavior: best.behaviorHint, rng: &rng
                )
                allPlans.append(ObjectPlan(
                    label: best.label,
                    scientific: best.scientific,
                    sourceClipR2Key: sampleR2Key(for: best),
                    startSec: t,
                    durationSec: best.durationSec,
                    positionCurve: [pos],
                    volume: 1.0,
                    loop: false,
                    behavior: best.behaviorHint,
                    locked: false
                ))
            }
        }

        if allPlans.count > 118 {
            allPlans = Array(allPlans.prefix(118))
        }
        return allPlans
    }

    /// Derive expected R2 key for the pre-extracted sample clip of this element.
    private func sampleR2Key(for el: SetData.Element) -> String {
        let speciesSlug = SetData.slugify(el.label)
        let confPct = Int(el.confidence * 100)
        let tStart = Int(el.timeSec)
        let filename = "\(speciesSlug)__\(el.sourceSlug)__t\(tStart)s__c\(String(format: "%03d", confPct)).m4a"
        return "samples/birds/\(speciesSlug)/\(filename)"
    }
}
