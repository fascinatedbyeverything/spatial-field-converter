import XCTest
@testable import SpatialFieldConverter

final class HigherOrderAmbisonicDecoderTests: XCTestCase {

    func test_thirdOrder_channelCount_is_16() {
        XCTAssertEqual(AmbisonicOrder.third.channelCount, 16)
        XCTAssertEqual(AmbisonicOrder.fromChannelCount(16), .third)
        XCTAssertEqual(AmbisonicOrder.fromChannelCount(4), .first)
        XCTAssertNil(AmbisonicOrder.fromChannelCount(7))
    }

    func test_zeroInput_producesZeroOutput() {
        let positions = VirtualLoudspeakerRig.atmos7_1_2().speakerPositions
        let decoder = HigherOrderAmbisonicDecoder(order: .third, speakerPositions: positions)
        let zeros = [Float](repeating: 0, count: 16 * 100)
        let out = decoder.decode(interleavedAmbisonic: zeros, frameCount: 100)
        XCTAssertEqual(out.count, 100 * 10)
        XCTAssertTrue(out.allSatisfy { abs($0) < 1e-6 })
    }

    func test_frontAxis_thirdOrderInput_concentratesEnergyOn_C_andL_R() {
        // Synthesize a unit plane wave from front (az=0, el=0) using the same SH function.
        // For front direction: X=1, all odd-azimuth harmonics → 0, so energy concentrates
        // heavily in the centre-front speaker (C).
        let frame = HigherOrderAmbisonicDecoder.sphericalHarmonics(azimuth: 0, elevation: 0, order: .third)
        XCTAssertEqual(frame.count, 16)

        let positions = VirtualLoudspeakerRig.atmos7_1_2().speakerPositions
        let decoder = HigherOrderAmbisonicDecoder(order: .third, speakerPositions: positions)
        let out = decoder.decode(ambisonicFrame: frame)

        // 7.1.2 channel order: L, R, C, LFE, Lss, Rss, Lrs, Rrs, Ltf, Rtf
        let l = out[0], r = out[1], c = out[2]
        let lrs = out[6], rrs = out[7]

        XCTAssertGreaterThan(c, 0, "C should be positive for front-axis source")
        XCTAssertGreaterThan(c, lrs, "C should dominate over rear surrounds for a front source")
        XCTAssertGreaterThan(c, rrs, "C should dominate over rear surrounds for a front source")
        // 3rd order should be MUCH more directional than 1st — the L/R bleed should be smaller
        // relative to C than at 1st order. We don't pin a number; just sanity check that L < C.
        XCTAssertLessThan(l, c)
        XCTAssertLessThan(r, c)
    }

    func test_directionalContrast_3rd_order_sharper_than_1st_order() {
        // Front-axis source. Compare ratio of (C output) / (rear surround output) for
        // 3rd-order vs 1st-order decoders. 3rd-order should produce a HIGHER ratio
        // (sharper localization) because higher-order SH provide better directional resolution.
        let positions = VirtualLoudspeakerRig.atmos7_1_2().speakerPositions

        let firstSH = HigherOrderAmbisonicDecoder.sphericalHarmonics(azimuth: 0, elevation: 0, order: .first)
        let firstDecoder = HigherOrderAmbisonicDecoder(order: .first, speakerPositions: positions)
        let outFirst = firstDecoder.decode(ambisonicFrame: firstSH)
        let firstRatio = outFirst[2] / max(abs(outFirst[6]), 1e-6)

        let thirdSH = HigherOrderAmbisonicDecoder.sphericalHarmonics(azimuth: 0, elevation: 0, order: .third)
        let thirdDecoder = HigherOrderAmbisonicDecoder(order: .third, speakerPositions: positions)
        let outThird = thirdDecoder.decode(ambisonicFrame: thirdSH)
        let thirdRatio = outThird[2] / max(abs(outThird[6]), 1e-6)

        XCTAssertGreaterThan(thirdRatio, firstRatio,
                             "3rd-order should be sharper than 1st-order at the same direction")
    }
}
