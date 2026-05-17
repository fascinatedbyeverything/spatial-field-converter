import XCTest
@testable import SpatialFieldConverter

final class SetCurationLogicTests: XCTestCase {

    func test_slugify_isStableAndLowercased() {
        XCTAssertEqual(SetData.slugify("Brazil Birds Morning"), "brazil-birds-morning")
        XCTAssertEqual(SetData.slugify("  Mixed   Spaces  "), "mixed-spaces")
        XCTAssertEqual(SetData.slugify("UPPER/case!chars"), SetData.slugify("upper-case-chars"))
    }

    func test_keptElements_filtersOnKeepFlag() {
        var set = SetFixtures.simpleSet(sustainedSeconds: [60], discreteCount: 5)
        let initial = set.keptElements.count
        XCTAssertGreaterThan(initial, 0)
        for i in set.elements.indices { set.elements[i].keep = false }
        XCTAssertEqual(set.keptElements.count, 0)
        for i in set.elements.indices { set.elements[i].keep = true }
        XCTAssertEqual(set.keptElements.count, set.elements.count)
    }

    @MainActor
    func test_renamingSet_andResavingSlugConsistency() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("CurationTests-\(UUID().uuidString)")
        let store = try SetStore(localDirectory: tmp)
        var set = SetFixtures.simpleSet(sustainedSeconds: [60], discreteCount: 2)
        set.name = "Renamed Set"
        set.slug = SetData.slugify(set.name)
        try store.saveLocal(set)
        let loaded = try store.loadLocal(slug: set.slug)
        XCTAssertEqual(loaded.name, "Renamed Set")
        XCTAssertEqual(loaded.slug, "renamed-set")
    }
}
