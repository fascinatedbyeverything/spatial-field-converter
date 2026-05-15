import XCTest
@testable import SpatialFieldConverter

final class VirtualLoudspeakerRigTests: XCTestCase {

    func test_speakerPositions_count_is10_for_7_1_2() {
        let rig = VirtualLoudspeakerRig.atmos7_1_2()
        XCTAssertEqual(rig.speakerPositions.count, 10)
    }

    func test_speakerOrder_matchesAtmosBedConvention() {
        let rig = VirtualLoudspeakerRig.atmos7_1_2()
        XCTAssertEqual(rig.speakerNames, ["L", "R", "C", "LFE", "Lss", "Rss", "Lrs", "Rrs", "Ltf", "Rtf"])
    }

    func test_decodingFrontBformat_putsEnergyOn_C_andOnFronts() {
        let rig = VirtualLoudspeakerRig.atmos7_1_2()
        // Front-only B-format: W=0.707, Y=0, Z=0, X=1 (AmbiX channel order W,Y,Z,X)
        let bformat: [Float] = [0.707, 0, 0, 1.0]
        let speakers = rig.decode(bformatFrame: bformat)

        XCTAssertEqual(speakers.count, 10)

        let c = speakers[2]
        let l = speakers[0]
        let r = speakers[1]
        let lrs = speakers[6]
        let rrs = speakers[7]

        XCTAssertGreaterThan(c, 0, "C should have positive energy for front-pointing source")
        XCTAssertGreaterThan(l, 0, "L should have positive energy")
        XCTAssertGreaterThan(r, 0, "R should have positive energy")
        XCTAssertLessThan(lrs, c, "Rear surrounds should be quieter than C for front source")
        XCTAssertLessThan(rrs, c, "Rear surrounds should be quieter than C for front source")
    }

    func test_decodingLeftBformat_putsMostEnergyOnLeftSpeakers() {
        let rig = VirtualLoudspeakerRig.atmos7_1_2()
        // Left-only B-format: W=0.707, Y=1, others 0
        let bformat: [Float] = [0.707, 1.0, 0, 0]
        let speakers = rig.decode(bformatFrame: bformat)

        let l = speakers[0]
        let r = speakers[1]
        let lss = speakers[4]
        let rss = speakers[5]

        XCTAssertGreaterThan(l, r, "L should be louder than R for left source")
        XCTAssertGreaterThan(lss, rss, "Lss should be louder than Rss for left source")
    }

    func test_lfeChannel_isBoundedForUnitW_singleFrame() {
        let rig = VirtualLoudspeakerRig.atmos7_1_2()
        // Pure W input — single-frame decoder (no time-domain filter yet, that's Task 3.2)
        let bformat: [Float] = [1.0, 0, 0, 0]
        let speakers = rig.decode(bformatFrame: bformat)
        let lfe = speakers[3]
        XCTAssertGreaterThanOrEqual(lfe, 0, "LFE should be non-negative for W=1 input")
        XCTAssertLessThanOrEqual(lfe, 1.0, "LFE single-frame contribution should not exceed unit input")
    }
}
