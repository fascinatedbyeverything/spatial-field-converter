import XCTest
@testable import SpatialFieldConverter

final class PositionAssignerTests: XCTestCase {

    func test_bird_speciesPlacedHighInHemisphere() {
        var rng = SeededGenerator(seed: 1)
        let pos = PositionAssigner.assign(label: "Great Kiskadee",
                                          kind: "species",
                                          behavior: .discrete,
                                          rng: &rng)
        XCTAssertGreaterThanOrEqual(pos.y, 0.4)
        XCTAssertLessThanOrEqual(pos.y, 0.9)
    }

    func test_wind_placedMid() {
        var rng = SeededGenerator(seed: 1)
        let pos = PositionAssigner.assign(label: "wind",
                                          kind: "category",
                                          behavior: .sustained,
                                          rng: &rng)
        XCTAssertGreaterThanOrEqual(pos.y, 0.0)
        XCTAssertLessThanOrEqual(pos.y, 0.4)
    }

    func test_water_placedAtHorizon() {
        var rng = SeededGenerator(seed: 1)
        let pos = PositionAssigner.assign(label: "water_flow",
                                          kind: "category",
                                          behavior: .sustained,
                                          rng: &rng)
        XCTAssertGreaterThanOrEqual(pos.y, -0.2)
        XCTAssertLessThanOrEqual(pos.y, 0.2)
    }

    func test_deterministicForSameSeed() {
        var rng1 = SeededGenerator(seed: 42)
        var rng2 = SeededGenerator(seed: 42)
        let p1 = PositionAssigner.assign(label: "Great Kiskadee", kind: "species",
                                         behavior: .discrete, rng: &rng1)
        let p2 = PositionAssigner.assign(label: "Great Kiskadee", kind: "species",
                                         behavior: .discrete, rng: &rng2)
        XCTAssertEqual(p1.x, p2.x); XCTAssertEqual(p1.y, p2.y); XCTAssertEqual(p1.z, p2.z)
    }

    func test_flybyCurve_traversesAcrossSpace() {
        var rng = SeededGenerator(seed: 7)
        let curve = PositionAssigner.flybyCurve(label: "Great Kiskadee",
                                                durationSec: 4.0,
                                                rng: &rng)
        XCTAssertGreaterThanOrEqual(curve.count, 2)
        XCTAssertEqual(curve.first?.timeSec, 0.0)
        XCTAssertEqual(curve.last?.timeSec, 4.0)
        XCTAssertNotEqual(curve.first?.x, curve.last?.x)
    }
}
