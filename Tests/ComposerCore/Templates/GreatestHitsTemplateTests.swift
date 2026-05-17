import XCTest
@testable import SpatialFieldConverter

final class GreatestHitsTemplateTests: XCTestCase {

    func test_schedule_emptySet_returnsEmpty() {
        let set = SetData(name: "x", slug: "x",
                          createdAt: Date(), updatedAt: Date(),
                          sources: [], elements: [])
        let tpl = GreatestHitsTemplate()
        let plans = tpl.schedule(set: set, durationSec: 300, seed: 1)
        XCTAssertEqual(plans.count, 0)
    }

    func test_schedule_placesMultipleInstancesPerSpecies() {
        let set = SetFixtures.simpleSet(sustainedSeconds: [], discreteCount: 2)
        let tpl = GreatestHitsTemplate()
        let plans = tpl.schedule(set: set, durationSec: 300, seed: 1)
        // 2 species × at least 2 placements each = ≥4
        XCTAssertGreaterThanOrEqual(plans.count, 2)
    }

    func test_schedule_deterministicForSameSeed() {
        let set = SetFixtures.simpleSet(sustainedSeconds: [], discreteCount: 3)
        let tpl = GreatestHitsTemplate()
        let a = tpl.schedule(set: set, durationSec: 300, seed: 42)
        let b = tpl.schedule(set: set, durationSec: 300, seed: 42)
        XCTAssertEqual(a.count, b.count)
        for i in 0..<a.count {
            XCTAssertEqual(a[i].startSec, b[i].startSec)
            XCTAssertEqual(a[i].label, b[i].label)
        }
    }

    func test_schedule_atmosCap_pruned() {
        var elements: [SetData.Element] = []
        for i in 0..<200 {
            elements.append(SetData.Element(
                id: "e-\(i)", label: "Species\(i)", scientific: nil,
                sourceSlug: "src", kind: "species",
                timeSec: 0, durationSec: 2, confidence: 0.5 + Double(i) * 0.001,
                behaviorHint: .discrete, keep: true))
        }
        let set = SetData(name: "x", slug: "x",
                          createdAt: Date(), updatedAt: Date(),
                          sources: [SetData.Source(slug: "src", category: "zoom-bounces")],
                          elements: elements)
        let tpl = GreatestHitsTemplate()
        let plans = tpl.schedule(set: set, durationSec: 300, seed: 1)
        XCTAssertLessThanOrEqual(plans.count, 118)
    }
}
