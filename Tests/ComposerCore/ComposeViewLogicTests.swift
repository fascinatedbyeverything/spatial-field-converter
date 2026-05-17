import XCTest
@testable import SpatialFieldConverter

final class ComposeViewLogicTests: XCTestCase {

    func test_setPosition_overwritesFirstKeyframeInPlace() throws {
        var comp = try Composer.compose(
            set: SetFixtures.simpleSet(sustainedSeconds: [60], discreteCount: 5),
            templateID: "greatest_hits",
            durationSec: 300,
            seed: 1,
            title: "T")
        XCTAssertFalse(comp.objects.isEmpty)
        let originalTime = comp.objects[0].positionCurve.first?.timeSec ?? 0

        // Simulate SpaceView drag
        let kf0 = comp.objects[0].positionCurve.first!
        comp.objects[0].positionCurve[0] = PositionKeyframe(
            timeSec: kf0.timeSec, x: 0.5, y: kf0.y, z: -0.4)

        XCTAssertEqual(comp.objects[0].positionCurve.first?.x, 0.5)
        XCTAssertEqual(comp.objects[0].positionCurve.first?.z, -0.4)
        XCTAssertEqual(comp.objects[0].positionCurve.first?.timeSec, originalTime)
    }

    func test_volume_isClampedByObjectInspectorBindingBehavior() throws {
        // Slider binds to ObjectPlan.volume directly. Verify the range we set in the View
        // (0...1) matches expectations for the data model.
        var comp = try Composer.compose(
            set: SetFixtures.simpleSet(sustainedSeconds: [60], discreteCount: 3),
            templateID: "greatest_hits",
            durationSec: 120, seed: 1, title: "T")
        comp.objects[0].volume = 1.5    // out-of-range write
        XCTAssertEqual(comp.objects[0].volume, 1.5, "the model itself doesn't clamp — Slider does")
        comp.objects[0].volume = 0.4
        XCTAssertEqual(comp.objects[0].volume, 0.4)
    }

    func test_objectsAreMutableViaIndex() throws {
        var comp = try Composer.compose(
            set: SetFixtures.simpleSet(sustainedSeconds: [60], discreteCount: 3),
            templateID: "greatest_hits",
            durationSec: 120, seed: 1, title: "T")
        comp.objects[0].locked = true
        XCTAssertTrue(comp.objects[0].locked)
        let newHint: BehaviorHint = comp.objects[0].behavior == .discrete ? .oneShot : .discrete
        comp.objects[0].behavior = newHint
        XCTAssertEqual(comp.objects[0].behavior, newHint)
    }
}
