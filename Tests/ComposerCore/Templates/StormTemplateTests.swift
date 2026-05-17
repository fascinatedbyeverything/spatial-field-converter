import XCTest
@testable import SpatialFieldConverter

final class StormTemplateTests: XCTestCase {
    func test_schedule_transientHeavy() {
        var elements: [SetData.Element] = []
        // 1 bird + 1 vehicle + 1 door (transients) + 1 wind sustained
        elements.append(SetData.Element(
            id: "b", label: "Cardinal", scientific: nil,
            sourceSlug: "s", kind: "species",
            timeSec: 0, durationSec: 2, confidence: 0.9,
            behaviorHint: .discrete, keep: true))
        elements.append(SetData.Element(
            id: "v", label: "car_passing_by", scientific: nil,
            sourceSlug: "s", kind: "category",
            timeSec: 0, durationSec: 3, confidence: 0.7,
            behaviorHint: .oneShot, keep: true))
        elements.append(SetData.Element(
            id: "d", label: "door", scientific: nil,
            sourceSlug: "s", kind: "category",
            timeSec: 0, durationSec: 1, confidence: 0.7,
            behaviorHint: .oneShot, keep: true))
        elements.append(SetData.Element(
            id: "w", label: "wind", scientific: nil,
            sourceSlug: "s", kind: "category",
            timeSec: 0, durationSec: 60, confidence: 0.8,
            behaviorHint: .sustained, keep: true))
        let set = SetData(name: "x", slug: "x", createdAt: Date(), updatedAt: Date(),
                          sources: [SetData.Source(slug: "s", category: "zoom-bounces")],
                          elements: elements)
        let tpl = StormTemplate()
        let plans = tpl.schedule(set: set, durationSec: 300, seed: 1)
        let oneShotCount = plans.filter { $0.behavior == .oneShot }.count
        let speciesCount = plans.filter { $0.behavior == .discrete }.count
        XCTAssertGreaterThan(oneShotCount, speciesCount, "storm should be transient-heavy")
    }
}
