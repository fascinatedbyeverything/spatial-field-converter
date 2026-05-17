import Foundation

/// spatial-mix/v2 manifest — the on-disk JSON description that Fascinated Field
/// and Presets3 load to play back a composed World.
///
/// Differences from v1:
///   - `objects[i].positionCurve` (array of {timeSec, x, y, z}) replaces single static position
///   - `objects[i].label`, `scientific` for species tagging
///   - `templateID` + `seed` for re-roll reproducibility
public struct WorldManifest: Codable, Equatable {
    public let schema: String          // "spatial-mix/v2"
    public let title: String
    public let slug: String
    public let durationSec: Double
    public let templateID: String
    public let seed: UInt64
    public let bed: BedRef
    public let objects: [ObjectRef]

    public struct BedRef: Codable, Equatable {
        public let file: String        // "bed.m4a" (relative)
    }

    public struct ObjectRef: Codable, Equatable {
        public let index: Int          // 1-based: matches obj-NN.m4a filename
        public let file: String        // "obj-01.m4a"
        public let label: String
        public let scientific: String?
        public let startSec: Double
        public let durationSec: Double
        public let volume: Double
        public let loop: Bool
        public let behavior: String    // BehaviorHint.rawValue
        public let positionCurve: [KeyframeRef]

        public struct KeyframeRef: Codable, Equatable {
            public let timeSec: Double
            public let x: Double
            public let y: Double
            public let z: Double
        }
    }

    enum CodingKeys: String, CodingKey {
        case schema
        case title
        case slug
        case durationSec = "duration_sec"
        case templateID = "template_id"
        case seed
        case bed
        case objects
    }
}

extension WorldManifest.ObjectRef {
    enum CodingKeys: String, CodingKey {
        case index
        case file
        case label
        case scientific
        case startSec = "start_sec"
        case durationSec = "duration_sec"
        case volume
        case loop
        case behavior
        case positionCurve = "position_curve"
    }
}

extension WorldManifest.ObjectRef.KeyframeRef {
    enum CodingKeys: String, CodingKey {
        case timeSec = "time_sec"
        case x
        case y
        case z
    }
}
