import XCTest
@testable import SpatialFieldConverter

final class CityPulseTemplateTests: XCTestCase {
    func test_schedule_transientHeavy() {
        var elements: [SetData.Element] = []
        elements.append(SetData.Element(
            id: "v", label: "car_passing_by", scientific: nil,
            sourceSlug: "s", kind: "category",
            timeSec: 0, durationSec: 3, confidence: 0.7,
            behaviorHint: .oneShot, keep: true))
        elements.append(SetData.Element(
            id: "v2", label: "vehicle_horn", scientific: nil,
            sourceSlug: "s", kind: "category",
            timeSec: 0, durationSec: 1, confidence: 0.7,
            behaviorHint: .oneShot, keep: true))
        elements.append(SetData.Element(
            id: "b", label: "Cardinal", scientific: nil,
            sourceSlug: "s", kind: "species",
            timeSec: 0, durationSec: 2, confidence: 0.9,
            behaviorHint: .discrete, keep: true))
        let set = SetData(name: "x", slug: "x", createdAt: Date(), updatedAt: Date(),
                          sources: [SetData.Source(slug: "s", category: "zoom-bounces")],
                          elements: elements)
        let tpl = CityPulseTemplate()
        let plans = tpl.schedule(set: set, durationSec: 300, seed: 1)
        let transient = plans.filter { $0.behavior == .oneShot }.count
        let nature = plans.filter { $0.behavior != .oneShot }.count
        XCTAssertGreaterThan(transient, nature, "city pulse should be transient-heavy")
    }
}
