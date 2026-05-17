import XCTest
@testable import SpatialFieldConverter

final class WorldManifestTests: XCTestCase {

    func test_roundtripsThroughJSON_snakeCase() throws {
        let manifest = WorldManifest(
            schema: "spatial-mix/v2",
            title: "Test",
            slug: "test-abc",
            durationSec: 300,
            templateID: "greatest_hits",
            seed: 42,
            bed: WorldManifest.BedRef(file: "bed.m4a"),
            objects: [
                WorldManifest.ObjectRef(
                    index: 1, file: "obj-01.m4a",
                    label: "Cardinal", scientific: "Cardinalis cardinalis",
                    startSec: 12.0, durationSec: 2.0,
                    volume: 1.0, loop: false, behavior: "discrete",
                    positionCurve: [
                        WorldManifest.ObjectRef.KeyframeRef(timeSec: 0, x: 0.3, y: 0.6, z: -0.2)
                    ])
            ])

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(manifest)
        let json = String(data: data, encoding: .utf8)!

        XCTAssertTrue(json.contains("\"duration_sec\""))
        XCTAssertTrue(json.contains("\"template_id\""))
        XCTAssertTrue(json.contains("\"start_sec\""))
        XCTAssertTrue(json.contains("\"position_curve\""))
        XCTAssertTrue(json.contains("\"time_sec\""))
        XCTAssertFalse(json.contains("\"durationSec\""))

        let decoded = try JSONDecoder().decode(WorldManifest.self, from: data)
        XCTAssertEqual(decoded, manifest)
    }
}
