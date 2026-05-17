import Foundation

/// A composition recipe. Given a Set + duration + seed, returns an ordered list of placed objects.
public protocol Template: Sendable {
    var id: String { get }
    var displayName: String { get }
    func schedule(set: SetData, durationSec: Double, seed: UInt64) -> [ObjectPlan]
}

/// Registry of shipping templates. Wire each new template here as it lands.
public enum TemplateRegistry {
    public static let all: [any Template] = [
        GreatestHitsTemplate(),
    ]

    public static func byID(_ id: String) -> (any Template)? {
        return all.first(where: { $0.id == id })
    }
}
