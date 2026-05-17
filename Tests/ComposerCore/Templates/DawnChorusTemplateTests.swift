import XCTest
@testable import SpatialFieldConverter

final class DawnChorusTemplateTests: XCTestCase {
    func test_schedule_birdHeavyDistribution() {
        var elements: [SetData.Element] = []
        for label in ["Cardinal", "Robin", "Thrush"] {
            elements.append(SetData.Element(
                id: label, label: label, scientific: nil,
                sourceSlug: "s", kind: "species",
                timeSec: 0, durationSec: 2, confidence: 0.9,
                behaviorHint: .discrete, keep: true))
        }
        elements.append(SetData.Element(
            id: "w", label: "wind", scientific: nil,
            sourceSlug: "s", kind: "category",
            timeSec: 0, durationSec: 30, confidence: 0.7,
            behaviorHint: .sustained, keep: true))
        elements.append(SetData.Element(
            id: "c", label: "car_passing_by", scientific: nil,
            sourceSlug: "s", kind: "category",
            timeSec: 0, durationSec: 3, confidence: 0.6,
            behaviorHint: .oneShot, keep: true))
        let set = SetData(name: "x", slug: "x",
                          createdAt: Date(), updatedAt: Date(),
                          sources: [SetData.Source(slug: "s", category: "zoom-bounces")],
                          elements: elements)
        let tpl = DawnChorusTemplate()
        let plans = tpl.schedule(set: set, durationSec: 300, seed: 1)
        let speciesCount = plans.filter { $0.behavior == .discrete }.count
        let nonSpeciesCount = plans.filter { $0.behavior == .oneShot }.count
        XCTAssertGreaterThan(Double(speciesCount), Double(plans.count) * 0.6)
        XCTAssertGreaterThan(speciesCount, nonSpeciesCount)
    }
}
