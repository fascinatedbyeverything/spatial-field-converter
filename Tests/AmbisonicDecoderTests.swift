import XCTest
@testable import SpatialFieldConverter

final class AmbisonicDecoderTests: XCTestCase {

    func test_zeroInput_producesZeroOutput() {
        let decoder = AmbisonicDecoder(matrix: VRH8DecoderMatrix.matrix)
        let input = SyntheticAmbisonicSignals.aFormatZero(frameCount: 100)
        let output = decoder.decode(interleavedAFormat: input, frameCount: 100)
        XCTAssertEqual(output.count, 100 * 4)
        XCTAssertTrue(output.allSatisfy { $0 == 0 })
    }

    func test_frontImpulse_X_isPositiveAndDominant() {
        let decoder = AmbisonicDecoder(matrix: VRH8DecoderMatrix.matrix)
        let input = SyntheticAmbisonicSignals.aFormatImpulse(directionX: 1, directionY: 0, directionZ: 0, frameCount: 4)
        let output = decoder.decode(interleavedAFormat: input, frameCount: 4)
        let w = output[0]
        let y = output[1]
        let z = output[2]
        let x = output[3]
        XCTAssertGreaterThan(x, 0.5, "X (front) should be strongly positive for front impulse")
        XCTAssertEqual(y, 0, accuracy: 1e-5, "Y should be ~0 for front impulse")
        XCTAssertEqual(z, 0, accuracy: 1e-5, "Z should be ~0 for front impulse")
        XCTAssertGreaterThan(w, 0, "W (omni) should be positive")
    }

    func test_leftImpulse_Y_isPositiveAndDominant() {
        let decoder = AmbisonicDecoder(matrix: VRH8DecoderMatrix.matrix)
        let input = SyntheticAmbisonicSignals.aFormatImpulse(directionX: 0, directionY: 1, directionZ: 0, frameCount: 4)
        let output = decoder.decode(interleavedAFormat: input, frameCount: 4)
        let y = output[1]
        let x = output[3]
        let z = output[2]
        XCTAssertGreaterThan(y, 0.5)
        XCTAssertEqual(x, 0, accuracy: 1e-5)
        XCTAssertEqual(z, 0, accuracy: 1e-5)
    }

    func test_upImpulse_Z_isPositiveAndDominant() {
        let decoder = AmbisonicDecoder(matrix: VRH8DecoderMatrix.matrix)
        let input = SyntheticAmbisonicSignals.aFormatImpulse(directionX: 0, directionY: 0, directionZ: 1, frameCount: 4)
        let output = decoder.decode(interleavedAFormat: input, frameCount: 4)
        let z = output[2]
        let x = output[3]
        let y = output[1]
        XCTAssertGreaterThan(z, 0.5)
        XCTAssertEqual(x, 0, accuracy: 1e-5)
        XCTAssertEqual(y, 0, accuracy: 1e-5)
    }

    func test_throughputProcessesLargeBuffer() {
        let decoder = AmbisonicDecoder(matrix: VRH8DecoderMatrix.matrix)
        let input = SyntheticAmbisonicSignals.aFormatNoise(frameCount: 48000)
        let output = decoder.decode(interleavedAFormat: input, frameCount: 48000)
        XCTAssertEqual(output.count, 48000 * 4)
    }
}
