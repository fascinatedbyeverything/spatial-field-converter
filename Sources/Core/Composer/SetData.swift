import Foundation

/// A user-curated palette of sound elements drawn from one or more analyzed recordings.
public struct SetData: Sendable, Codable, Equatable {

    public let schema: String
    public var name: String
    public var slug: String
    public let createdAt: Date
    public var updatedAt: Date
    public var sources: [Source]
    public var elements: [Element]

    public init(name: String,
                slug: String,
                createdAt: Date,
                updatedAt: Date,
                sources: [Source],
                elements: [Element]) {
        self.schema = "set/v1"
        self.name = name
        self.slug = slug
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sources = sources
        self.elements = elements
    }

    public var keptElements: [Element] { elements.filter { $0.keep } }

    public static func slugify(_ raw: String) -> String {
        let lowered = raw.lowercased()
        var out = ""
        var lastDash = true
        for scalar in lowered.unicodeScalars {
            let isAlnum = (scalar >= "a" && scalar <= "z") || (scalar >= "0" && scalar <= "9")
            if isAlnum {
                out.unicodeScalars.append(scalar)
                lastDash = false
            } else if !lastDash {
                out.append("-")
                lastDash = true
            }
        }
        while out.hasSuffix("-") { out.removeLast() }
        return out
    }

    public struct Source: Sendable, Codable, Equatable {
        public let slug: String
        public let category: String
        public init(slug: String, category: String) {
            self.slug = slug
            self.category = category
        }
    }

    public struct Element: Sendable, Codable, Equatable, Identifiable {
        public let id: String
        public var label: String
        public var scientific: String?
        public let sourceSlug: String
        public let kind: String
        public let timeSec: Double
        public let durationSec: Double
        public let confidence: Double
        public var behaviorHint: BehaviorHint
        public var keep: Bool

        public init(id: String, label: String, scientific: String?,
                    sourceSlug: String, kind: String,
                    timeSec: Double, durationSec: Double, confidence: Double,
                    behaviorHint: BehaviorHint, keep: Bool) {
            self.id = id; self.label = label; self.scientific = scientific
            self.sourceSlug = sourceSlug; self.kind = kind
            self.timeSec = timeSec; self.durationSec = durationSec
            self.confidence = confidence
            self.behaviorHint = behaviorHint; self.keep = keep
        }

        private enum CodingKeys: String, CodingKey {
            case id, label, scientific
            case sourceSlug = "source_slug"
            case kind
            case timeSec = "time_sec"
            case durationSec = "duration_sec"
            case confidence
            case behaviorHint = "behavior_hint"
            case keep
        }
    }

    private enum CodingKeys: String, CodingKey {
        case schema, name, slug
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case sources, elements
    }
}
