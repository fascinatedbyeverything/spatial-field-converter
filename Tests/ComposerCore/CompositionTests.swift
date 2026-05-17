import XCTest
@testable import SpatialFieldConverter

final class CompositionTests: XCTestCase {
    func test_positionKeyframe_clampedToValidRange() {
        let k = PositionKeyframe(timeSec: 0, x: 2.5, y: -3.0, z: 0.5)
        XCTAssertEqual(k.x, 1.0)
        XCTAssertEqual(k.y, -1.0)
        XCTAssertEqual(k.z, 0.5)
    }

    func test_objectPlan_isAnimated_trueForFlybyBehavior() {
        let plan = ObjectPlan(
            label: "Cardinal", scientific: nil,
            sourceClipR2Key: "samples/birds/cardinal/clip.m4a",
            startSec: 12.0, durationSec: 4.0,
            positionCurve: [PositionKeyframe(timeSec: 0, x: 0, y: 0.5, z: 0)],
            volume: 0.9, loop: false, behavior: .flyby, locked: false
        )
        XCTAssertTrue(plan.isAnimated)
    }

    func test_objectPlan_isAnimated_falseForSingleKeyframeNonFlyby() {
        let plan = ObjectPlan(
            label: "Cardinal", scientific: nil,
            sourceClipR2Key: "samples/birds/cardinal/clip.m4a",
            startSec: 12.0, durationSec: 4.0,
            positionCurve: [PositionKeyframe(timeSec: 0, x: 0, y: 0.5, z: 0)],
            volume: 0.9, loop: false, behavior: .discrete, locked: false
        )
        XCTAssertFalse(plan.isAnimated)
    }

    func test_composition_atmosObjectBudget_is118() {
        var objs: [ObjectPlan] = []
        for i in 0..<200 {
            objs.append(ObjectPlan(
                label: "obj\(i)", scientific: nil,
                sourceClipR2Key: "k", startSec: Double(i),
                durationSec: 1.0, positionCurve: [], volume: 1.0,
                loop: false, behavior: .discrete, locked: false
            ))
        }
        let bed = BedPlan(segments: [], crossfadeMs: 1500)
        let c = Composition(bed: bed, objects: objs, durationSec: 300.0)
        XCTAssertEqual(c.atmosObjectBudget, 118)
    }
}
