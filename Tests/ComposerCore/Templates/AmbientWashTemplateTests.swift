import XCTest
@testable import SpatialFieldConverter

final class AmbientWashTemplateTests: XCTestCase {
    func test_schedule_sparseEvents_evenDistribution() {
        let set = SetFixtures.simpleSet(sustainedSeconds: [60], discreteCount: 8)
        let tpl = AmbientWashTemplate()
        let plans = tpl.schedule(set: set, durationSec: 300, seed: 1)
        let expected = max(8, Int(300.0 / 30.0))   // 10
        XCTAssertEqual(plans.count, expected)
    }
}
