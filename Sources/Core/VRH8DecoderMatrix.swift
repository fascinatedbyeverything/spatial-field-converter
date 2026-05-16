import Foundation

/// Reference 4×4 conversion matrix for Zoom VRH-8 A-format → AmbiX B-format.
///
/// Input channel order (rows of input frames):  FLU, FRD, BLD, BRU
/// Output channel order (rows of output frames): W, Y, Z, X  (ACN ordering, SN3D normalization)
///
/// These are the standard reference coefficients (Daniel 2000, EBU Tech 3285 conventions).
/// Per-capsule calibration trim is deferred to v0.2.
public enum VRH8DecoderMatrix {

    /// matrix[outChannel][inChannel].
    /// outChannel: 0=W, 1=Y, 2=Z, 3=X (ACN order, 1st-order ambisonics)
    /// inChannel:  0=FLU, 1=FRD, 2=BLD, 3=BRU (VRH-8 capsule order)
    public static let matrix: [[Float]] = [
        // W = (FLU + FRD + BLD + BRU) / 2
        [ 0.5,  0.5,  0.5,  0.5],
        // Y = (FLU - FRD + BLD - BRU) / 2
        [ 0.5, -0.5,  0.5, -0.5],
        // Z = (FLU + FRD - BLD - BRU) / 2
        [ 0.5,  0.5, -0.5, -0.5],
        // X = (FLU - FRD - BLD + BRU) / 2
        [ 0.5, -0.5, -0.5,  0.5]
    ]

    public static let inputChannelCount = 4
    public static let outputChannelCount = 4
}
