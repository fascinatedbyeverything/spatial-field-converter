import XCTest
@testable import SpatialFieldConverter

final class EventSchedulerTests: XCTestCase {

    func test_uniform_distributesNTimesAcrossDuration() {
        var rng = SeededGenerator(seed: 1)
        let times = EventScheduler.uniform(count: 5, durationSec: 100.0, jitter: 0.0, rng: &rng)
        XCTAssertEqual(times.count, 5)
        XCTAssertEqual(times[0], 0.0, accuracy: 0.01)
        XCTAssertEqual(times[4], 100.0, accuracy: 0.01)
    }

    func test_uniform_jitterMovesTimesWithinSlots() {
        var rng1 = SeededGenerator(seed: 1)
        var rng2 = SeededGenerator(seed: 2)
        let a = EventScheduler.uniform(count: 5, durationSec: 100.0, jitter: 0.5, rng: &rng1)
        let b = EventScheduler.uniform(count: 5, durationSec: 100.0, jitter: 0.5, rng: &rng2)
        XCTAssertNotEqual(a, b)
        for t in a { XCTAssertGreaterThanOrEqual(t, 0); XCTAssertLessThanOrEqual(t, 100) }
    }

    func test_rampIn_concentratesLateEvents() {
        var rng = SeededGenerator(seed: 1)
        let times = EventScheduler.rampIn(count: 20, durationSec: 100.0, rng: &rng)
        let firstHalf = times.filter { $0 < 50 }.count
        let secondHalf = times.filter { $0 >= 50 }.count
        XCTAssertLessThan(firstHalf, secondHalf, "ramp-in should put more events later")
    }

    func test_sparseRandom_returnsRequestedCount() {
        var rng = SeededGenerator(seed: 1)
        let times = EventScheduler.sparseRandom(count: 3, durationSec: 60.0, rng: &rng)
        XCTAssertEqual(times.count, 3)
        for t in times { XCTAssertGreaterThanOrEqual(t, 0); XCTAssertLessThanOrEqual(t, 60) }
    }

    func test_deterministic_sameSeedSameOutput() {
        var r1 = SeededGenerator(seed: 99)
        var r2 = SeededGenerator(seed: 99)
        let a = EventScheduler.uniform(count: 10, durationSec: 60.0, jitter: 0.3, rng: &r1)
        let b = EventScheduler.uniform(count: 10, durationSec: 60.0, jitter: 0.3, rng: &r2)
        XCTAssertEqual(a, b)
    }
}
