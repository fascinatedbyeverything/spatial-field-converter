import Foundation

/// How a Set element should behave in the composed World.
public enum BehaviorHint: String, Codable, Sendable, Equatable, CaseIterable {
    case sustained      // ambient pad — feeds the bed
    case discrete       // one-off placement, static position
    case oneShot        // single instance, no looping, transient
    case flyby          // motion across the soundfield

    /// Default behavior for a given category label.
    public static func defaultFor(category: String) -> BehaviorHint {
        let lower = category.lowercased()
        let sustainedKeywords = ["wind", "water", "rain", "cricket", "insect",
                                 "leaf_rustle", "ocean", "river", "stream", "ambience"]
        if sustainedKeywords.contains(where: { lower.contains($0) }) {
            return .sustained
        }
        let oneShotKeywords = ["door", "car_passing", "vehicle_horn", "siren", "bell",
                               "knock", "footstep", "thud", "bang", "crash", "gunshot"]
        if oneShotKeywords.contains(where: { lower.contains($0) }) {
            return .oneShot
        }
        return .discrete
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let value = BehaviorHint(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "unknown BehaviorHint: \(raw)"
            )
        }
        self = value
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(self.rawValue)
    }

    public var rawValue: String {
        switch self {
        case .sustained: return "sustained"
        case .discrete: return "discrete"
        case .oneShot: return "one_shot"
        case .flyby: return "flyby"
        }
    }

    public init?(rawValue: String) {
        switch rawValue {
        case "sustained": self = .sustained
        case "discrete": self = .discrete
        case "one_shot": self = .oneShot
        case "flyby": self = .flyby
        default: return nil
        }
    }
}
