import XCTest
@testable import SpatialFieldConverter

@MainActor
final class SetStoreTests: XCTestCase {

    private func makeTempStore() throws -> SetStore {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("SetStoreTests-\(UUID().uuidString)", isDirectory: true)
        return try SetStore(localDirectory: tmp)
    }

    func test_save_and_load_roundtripsLocally() throws {
        let store = try makeTempStore()
        let original = SetFixtures.simpleSet(sustainedSeconds: [60], discreteCount: 3)
        try store.saveLocal(original)
        let loaded = try store.loadLocal(slug: original.slug)
        XCTAssertEqual(loaded.slug, original.slug)
        XCTAssertEqual(loaded.elements.count, original.elements.count)
        XCTAssertEqual(loaded.sources.count, original.sources.count)
    }

    func test_listLocalSlugs_returnsAllSavedSlugs() throws {
        let store = try makeTempStore()
        let a = SetFixtures.simpleSet(sustainedSeconds: [60], discreteCount: 1)
        let b = SetData(name: "Other", slug: "other-set",
                        createdAt: Date(), updatedAt: Date(),
                        sources: [SetData.Source(slug: "s", category: "zoom-bounces")],
                        elements: [])
        try store.saveLocal(a)
        try store.saveLocal(b)
        let slugs = Set(store.listLocalSlugs())
        XCTAssertTrue(slugs.contains(a.slug))
        XCTAssertTrue(slugs.contains(b.slug))
    }

    func test_delete_removesFromLocalDir() throws {
        let store = try makeTempStore()
        let a = SetFixtures.simpleSet(sustainedSeconds: [60], discreteCount: 1)
        try store.saveLocal(a)
        XCTAssertTrue(store.listLocalSlugs().contains(a.slug))
        try store.deleteLocal(slug: a.slug)
        XCTAssertFalse(store.listLocalSlugs().contains(a.slug))
    }

    func test_load_unknownSlug_throws() throws {
        let store = try makeTempStore()
        XCTAssertThrowsError(try store.loadLocal(slug: "no-such-slug"))
    }

    func test_jsonOnDisk_isSnakeCase() throws {
        let store = try makeTempStore()
        let a = SetFixtures.simpleSet(sustainedSeconds: [60], discreteCount: 1)
        try store.saveLocal(a)
        let url = store.localStorageURL.appendingPathComponent("\(a.slug).json")
        let text = String(data: try Data(contentsOf: url), encoding: .utf8) ?? ""
        // SetData.CodingKeys encodes createdAt as "created_at" (snake_case).
        XCTAssertTrue(text.contains("\"created_at\""),
                      "JSON file must use snake_case 'created_at': \(text.prefix(400))")
        XCTAssertTrue(text.contains("\"updated_at\""),
                      "JSON file must use snake_case 'updated_at': \(text.prefix(400))")
    }
}
