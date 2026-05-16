import Foundation

/// Sample rate and bit depth supported by the Dolby Atmos Master ADM Profile v1.0.
public enum ADMSampleRate: Int, Sendable {
    case hz48000 = 48000
}

public enum ADMBitDepth: Int, Sendable {
    case bits24 = 24
}

/// Configuration for the Atmos 7.1.2 bed pack. Single config for v0.1.
public struct ADMBedConfig: Sendable {
    public static let channelCount: Int = 10
    public static let packFormatID: String = "AP_00010003"   // BS.2094 7.1.2 surround pack

    /// AmbiX/Atmos 7.1.2 channel order with BS.2094 channelFormat IDs.
    public static let channels: [(name: String, channelFormatID: String)] = [
        ("L",   "AC_00010001"),
        ("R",   "AC_00010002"),
        ("C",   "AC_00010003"),
        ("LFE", "AC_00010004"),
        ("Lss", "AC_00010005"),
        ("Rss", "AC_00010006"),
        ("Lrs", "AC_00010007"),
        ("Rrs", "AC_00010008"),
        ("Ltf", "AC_00010013"),
        ("Rtf", "AC_00010014"),
    ]
}

/// All metadata needed to write a 7.1.2 bed ADM BWF master.
public struct ADMBedSession: Sendable {
    public let programmeName: String
    public let sampleRate: ADMSampleRate
    public let bitDepth: ADMBitDepth

    public init(programmeName: String,
                sampleRate: ADMSampleRate = .hz48000,
                bitDepth: ADMBitDepth = .bits24) {
        self.programmeName = programmeName
        self.sampleRate = sampleRate
        self.bitDepth = bitDepth
    }
}
