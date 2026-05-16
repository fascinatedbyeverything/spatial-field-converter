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

    func test_lfeStream_lowPassesAt80Hz() {
        let rig = VirtualLoudspeakerRig.atmos7_1_2()
        let processor1 = rig.makeStreamingDecoder(sampleRate: 48000)

        // 1 second of 1 kHz tone in W only
        let frameCount = 48000
        var input = [Float](repeating: 0, count: frameCount * 4)
        for f in 0..<frameCount {
            let t = Float(f) / 48000.0
            input[f * 4 + 0] = sin(2 * .pi * 1000 * t) * 0.5
        }
        let output = processor1.process(interleavedBformat: input, frameCount: frameCount)
        let speakerCount = 10

        var lfeRms: Float = 0
        for f in 0..<frameCount {
            let s = output[f * speakerCount + 3]
            lfeRms += s * s
        }
        lfeRms = sqrt(lfeRms / Float(frameCount))
        XCTAssertLessThan(lfeRms, 0.01, "LFE should attenuate a 1kHz tone heavily")

        // 50 Hz: should pass through with much higher energy
        var input50 = [Float](repeating: 0, count: frameCount * 4)
        for f in 0..<frameCount {
            let t = Float(f) / 48000.0
            input50[f * 4 + 0] = sin(2 * .pi * 50 * t) * 0.5
        }
        let processor2 = rig.makeStreamingDecoder(sampleRate: 48000)
        let output50 = processor2.process(interleavedBformat: input50, frameCount: frameCount)
        var lfeRms50: Float = 0
        for f in 0..<frameCount {
            let s = output50[f * speakerCount + 3]
            lfeRms50 += s * s
        }
        lfeRms50 = sqrt(lfeRms50 / Float(frameCount))
        XCTAssertGreaterThan(lfeRms50, lfeRms * 10, "50Hz should pass through LFE much more than 1kHz")
    }
}
