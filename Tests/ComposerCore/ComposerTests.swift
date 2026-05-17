import XCTest
@testable import SpatialFieldConverter

final class ComposerTests: XCTestCase {

    func test_compose_producesBedPlanAndObjectPlans() throws {
        let set = SetFixtures.simpleSet(sustainedSeconds: [60], discreteCount: 5)
        let comp = try Composer.compose(
            set: set,
            templateID: "greatest_hits",
            durationSec: 300,
            seed: 42,
            title: "Test World"
        )
        XCTAssertFalse(comp.bedPlan.segments.isEmpty, "should produce a bed")
        XCTAssertFalse(comp.objects.isEmpty, "should produce objects")
        XCTAssertEqual(comp.durationSec, 300)
        XCTAssertEqual(comp.seed, 42)
        XCTAssertEqual(comp.templateID, "greatest_hits")
        XCTAssertEqual(comp.title, "Test World")
        XCTAssertFalse(comp.slug?.isEmpty ?? true)
    }

    func test_compose_isDeterministicForSameSeed() throws {
        let set = SetFixtures.simpleSet(sustainedSeconds: [60], discreteCount: 5)
        let a = try Composer.compose(
            set: set, templateID: "greatest_hits",
            durationSec: 300, seed: 42, title: "Test")
        let b = try Composer.compose(
            set: set, templateID: "greatest_hits",
            durationSec: 300, seed: 42, title: "Test")
        XCTAssertEqual(a.objects.count, b.objects.count)
        // Same seed = same start times in same order
        let aStarts = a.objects.map { $0.startSec }
        let bStarts = b.objects.map { $0.startSec }
        XCTAssertEqual(aStarts, bStarts, "same seed must produce identical schedule")
    }

    func test_compose_differentSeedsDiffer() throws {
        let set = SetFixtures.simpleSet(sustainedSeconds: [60], discreteCount: 5)
        let a = try Composer.compose(
            set: set, templateID: "greatest_hits",
            durationSec: 300, seed: 1, title: "Test")
        let b = try Composer.compose(
            set: set, templateID: "greatest_hits",
            durationSec: 300, seed: 2, title: "Test")
        let aStarts = a.objects.map { $0.startSec }
        let bStarts = b.objects.map { $0.startSec }
        XCTAssertNotEqual(aStarts, bStarts, "different seeds should produce different schedule")
    }

    func test_compose_unknownTemplateThrows() {
        let set = SetFixtures.simpleSet(sustainedSeconds: [60], discreteCount: 5)
        XCTAssertThrowsError(try Composer.compose(
            set: set, templateID: "no_such_template",
            durationSec: 300, seed: 1, title: "Test"))
    }

    func test_compose_capsObjectsAt118() throws {
        // Build a set with a LOT of discrete elements so templates would emit >118
        let set = SetFixtures.simpleSet(sustainedSeconds: [60], discreteCount: 200)
        let comp = try Composer.compose(
            set: set, templateID: "greatest_hits",
            durationSec: 600, seed: 1, title: "Big")
        XCTAssertLessThanOrEqual(comp.objects.count, 118, "Atmos cap is 118 objects")
    }

    func test_compose_slug_isDeterministicFromTitle() throws {
        let set = SetFixtures.simpleSet(sustainedSeconds: [60], discreteCount: 5)
        let a = try Composer.compose(
            set: set, templateID: "greatest_hits",
            durationSec: 300, seed: 42, title: "My Forest World")
        let b = try Composer.compose(
            set: set, templateID: "greatest_hits",
            durationSec: 300, seed: 42, title: "My Forest World")
        XCTAssertEqual(a.slug, b.slug, "same title + seed = same slug")
        let aSlug = try XCTUnwrap(a.slug)
        XCTAssertTrue(aSlug.contains("my-forest-world"), "slug should reflect sanitized title: \(aSlug)")
    }
}
