import XCTest
@testable import SpatialFieldConverter

final class SetDataTests: XCTestCase {
    func test_behaviorHint_codable_roundtrip() throws {
        let original: [BehaviorHint] = [.sustained, .discrete, .oneShot, .flyby]
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode([BehaviorHint].self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func test_behaviorHint_jsonStringValues() throws {
        let data = try JSONEncoder().encode(BehaviorHint.oneShot)
        let str = String(data: data, encoding: .utf8)
        XCTAssertEqual(str, "\"one_shot\"")
    }

    func test_behaviorHint_defaultForCategory() {
        XCTAssertEqual(BehaviorHint.defaultFor(category: "bird"), .discrete)
        XCTAssertEqual(BehaviorHint.defaultFor(category: "wind"), .sustained)
        XCTAssertEqual(BehaviorHint.defaultFor(category: "water_flow"), .sustained)
        XCTAssertEqual(BehaviorHint.defaultFor(category: "door"), .oneShot)
        XCTAssertEqual(BehaviorHint.defaultFor(category: "car_passing_by"), .oneShot)
        XCTAssertEqual(BehaviorHint.defaultFor(category: "unknown_category"), .discrete)
    }

    func test_setData_jsonRoundtrip() throws {
        let original = SetData(
            name: "Brazil Forest Morning",
            slug: "brazil-morning",
            createdAt: Date(timeIntervalSince1970: 1747000000),
            updatedAt: Date(timeIntervalSince1970: 1747000000),
            sources: [
                SetData.Source(slug: "field-recording-2024-10-18-52df6e",
                               category: "zoom-bounces")
            ],
            elements: [
                SetData.Element(id: "uuid-1",
                                label: "Great Kiskadee",
                                scientific: "Pitangus sulphuratus",
                                sourceSlug: "field-recording-2024-10-18-52df6e",
                                kind: "species",
                                timeSec: 142.5,
                                durationSec: 11.5,
                                confidence: 0.98,
                                behaviorHint: .discrete,
                                keep: true),
                SetData.Element(id: "uuid-2",
                                label: "wind",
                                scientific: nil,
                                sourceSlug: "field-recording-2024-10-18-52df6e",
                                kind: "category",
                                timeSec: 200.0,
                                durationSec: 30.0,
                                confidence: 0.71,
                                behaviorHint: .sustained,
                                keep: true)
            ]
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let data = try encoder.encode(original)
        let decoded = try JSONDecoder().decode(SetData.self, from: data)

        XCTAssertEqual(decoded.name, "Brazil Forest Morning")
        XCTAssertEqual(decoded.slug, "brazil-morning")
        XCTAssertEqual(decoded.sources.count, 1)
        XCTAssertEqual(decoded.elements.count, 2)
        XCTAssertEqual(decoded.elements[0].label, "Great Kiskadee")
        XCTAssertEqual(decoded.elements[0].behaviorHint, .discrete)
        XCTAssertEqual(decoded.elements[1].behaviorHint, .sustained)
        XCTAssertEqual(decoded.schema, "set/v1")
    }

    func test_setData_keptElements_filtersByKeep() {
        let s = SetData(name: "x", slug: "x", createdAt: Date(), updatedAt: Date(),
                        sources: [],
                        elements: [
                            SetData.Element(id: "1", label: "Bird", scientific: nil,
                                            sourceSlug: "s", kind: "species",
                                            timeSec: 0, durationSec: 1, confidence: 0.5,
                                            behaviorHint: .discrete, keep: true),
                            SetData.Element(id: "2", label: "Siren", scientific: nil,
                                            sourceSlug: "s", kind: "category",
                                            timeSec: 1, durationSec: 1, confidence: 0.5,
                                            behaviorHint: .oneShot, keep: false)
                        ])
        XCTAssertEqual(s.keptElements.count, 1)
        XCTAssertEqual(s.keptElements[0].label, "Bird")
    }

    func test_setData_slugify() {
        XCTAssertEqual(SetData.slugify("Brazil Forest Morning"), "brazil-forest-morning")
        XCTAssertEqual(SetData.slugify("Wrigley Field (2024)"), "wrigley-field-2024")
        XCTAssertEqual(SetData.slugify("  Multi    Spaces  "), "multi-spaces")
    }
}
