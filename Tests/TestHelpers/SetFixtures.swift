import Foundation
@testable import SpatialFieldConverter

enum SetFixtures {
    static func simpleSet(sustainedSeconds: [Double] = [60, 45, 30],
                          discreteCount: Int = 5,
                          source: String = "test-source") -> SetData {
        var elements: [SetData.Element] = []
        var t: Double = 0
        for (i, dur) in sustainedSeconds.enumerated() {
            elements.append(SetData.Element(
                id: "sus-\(i)", label: "wind",
                scientific: nil, sourceSlug: source,
                kind: "category", timeSec: t,
                durationSec: dur, confidence: 0.6,
                behaviorHint: .sustained, keep: true))
            t += dur + 5
        }
        for i in 0..<discreteCount {
            elements.append(SetData.Element(
                id: "disc-\(i)", label: "Great Kiskadee",
                scientific: "Pitangus sulphuratus", sourceSlug: source,
                kind: "species", timeSec: Double(i) * 30,
                durationSec: 2.0, confidence: 0.95,
                behaviorHint: .discrete, keep: true))
        }
        return SetData(
            name: "fixture", slug: "fixture",
            createdAt: Date(), updatedAt: Date(),
            sources: [SetData.Source(slug: source, category: "zoom-bounces")],
            elements: elements)
    }
}
