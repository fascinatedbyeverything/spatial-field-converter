import XCTest
@testable import SpatialFieldConverter

final class SoloBirdTemplateTests: XCTestCase {
    func test_schedule_featuresTopConfidenceSpecies() {
        var elements: [SetData.Element] = []
        elements.append(SetData.Element(id: "a", label: "Cardinal", scientific: nil,
                                        sourceSlug: "s", kind: "species",
                                        timeSec: 0, durationSec: 2, confidence: 0.95,
                                        behaviorHint: .discrete, keep: true))
        elements.append(SetData.Element(id: "b", label: "Robin", scientific: nil,
                                        sourceSlug: "s", kind: "species",
                                        timeSec: 0, durationSec: 2, confidence: 0.5,
                                        behaviorHint: .discrete, keep: true))
        let set = SetData(name: "x", slug: "x", createdAt: Date(), updatedAt: Date(),
                          sources: [SetData.Source(slug: "s", category: "zoom-bounces")],
                          elements: elements)
        let tpl = SoloBirdTemplate()
        let plans = tpl.schedule(set: set, durationSec: 300, seed: 1)
        let cardinalCount = plans.filter { $0.label == "Cardinal" }.count
        let robinCount = plans.filter { $0.label == "Robin" }.count
        XCTAssertGreaterThan(cardinalCount, robinCount)
    }
}
