import Foundation

/// Sennheiser Ambeo VR Mic — A-format to B-format AmbiX decode matrix.
/// Input channel order: FLU, FRD, BLD, BRU
/// Output: W, Y, Z, X (ACN/SN3D)
///
/// Reference: Sennheiser AMBEO A-B Format Converter plugin specifications.
/// v1.0 ships the reference (±0.5) matrix. Per-capsule calibration trim is v1.1+ work.
public enum AmbeoDecoderMatrix {

    /// matrix[outChannel][inChannel].
    /// outChannel: 0=W, 1=Y, 2=Z, 3=X (ACN order)
    /// inChannel:  0=FLU, 1=FRD, 2=BLD, 3=BRU
    public static let matrix: [[Float]] = [
        // W = 0.5 * (FLU + FRD + BLD + BRU)
        [ 0.5,  0.5,  0.5,  0.5],
        // Y = 0.5 * (FLU - FRD + BLD - BRU)
        [ 0.5, -0.5,  0.5, -0.5],
        // Z = 0.5 * (FLU + FRD - BLD - BRU)
        [ 0.5,  0.5, -0.5, -0.5],
        // X = 0.5 * (FLU - FRD - BLD + BRU)
        [ 0.5, -0.5, -0.5,  0.5]
    ]

    public static let inputChannelCount = 4
    public static let outputChannelCount = 4
}
