import XCTest
@testable import SpatialFieldConverter

final class BedPlannerTests: XCTestCase {

    func test_plan_singleSustainedSegmentLoopedToFillDuration() {
        let set = SetFixtures.simpleSet(sustainedSeconds: [60])
        let plan = BedPlanner.plan(set: set, targetDurationSec: 180, crossfadeMs: 1500)
        XCTAssertGreaterThanOrEqual(plan.segments.count, 3)
        XCTAssertEqual(plan.crossfadeMs, 1500)
    }

    func test_plan_multipleSustainedSegmentsStitched() {
        let set = SetFixtures.simpleSet(sustainedSeconds: [60, 40, 30])
        let plan = BedPlanner.plan(set: set, targetDurationSec: 200, crossfadeMs: 1500)
        XCTAssertGreaterThanOrEqual(plan.segments.count, 3)
        let totalCoverage = plan.segments.reduce(0.0) { $0 + ($1.endInClipSec - $1.startInClipSec) }
        XCTAssertGreaterThanOrEqual(totalCoverage, 200.0)
    }

    func test_plan_noSustainedElements_returnsEmptyBed() {
        var s = SetFixtures.simpleSet(sustainedSeconds: [60])
        for i in 0..<s.elements.count {
            if s.elements[i].behaviorHint == .sustained {
                s.elements[i].keep = false
            }
        }
        let plan = BedPlanner.plan(set: s, targetDurationSec: 180, crossfadeMs: 1500)
        XCTAssertEqual(plan.segments.count, 0)
    }

    func test_plan_segmentReferencesSourceBedR2Key() {
        let set = SetFixtures.simpleSet(sustainedSeconds: [60], source: "myslug")
        let plan = BedPlanner.plan(set: set, targetDurationSec: 60, crossfadeMs: 1500)
        XCTAssertTrue(plan.segments[0].sourceClipR2Key.contains("myslug"))
        XCTAssertTrue(plan.segments[0].sourceClipR2Key.hasSuffix("/bed.m4a"))
    }
}
