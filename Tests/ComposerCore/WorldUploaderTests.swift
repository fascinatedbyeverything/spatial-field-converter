import XCTest
@testable import SpatialFieldConverter

@MainActor
final class WorldUploaderTests: XCTestCase {

    func test_init_succeeds() {
        let u = WorldUploader()
        XCTAssertNotNil(u)
    }
}
