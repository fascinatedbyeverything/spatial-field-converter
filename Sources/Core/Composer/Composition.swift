import Foundation

/// Final structured output of the Composer. Drives WorldRenderer.
public struct Composition: Sendable {
    public let bed: BedPlan
    public let objects: [ObjectPlan]
    public let durationSec: Double

    /// Dolby Atmos master limit on dynamic objects.
    public let atmosObjectBudget: Int = 118

    public init(bed: BedPlan, objects: [ObjectPlan], durationSec: Double) {
        self.bed = bed
        self.objects = objects
        self.durationSec = durationSec
    }
}

/// Recipe for stitching ambient bed audio.
public struct BedPlan: Sendable {
    public let segments: [BedSegment]
    public let crossfadeMs: Int

    public init(segments: [BedSegment], crossfadeMs: Int) {
        self.segments = segments
        self.crossfadeMs = crossfadeMs
    }
}

public struct BedSegment: Sendable {
    public let sourceClipR2Key: String
    public let startInClipSec: Double
    public let endInClipSec: Double

    public init(sourceClipR2Key: String, startInClipSec: Double, endInClipSec: Double) {
        self.sourceClipR2Key = sourceClipR2Key
        self.startInClipSec = startInClipSec
        self.endInClipSec = endInClipSec
    }
}

/// One placed sound event in the World.
public struct ObjectPlan: Sendable, Identifiable, Equatable {
    public let id: UUID
    public var label: String
    public var scientific: String?
    public var sourceClipR2Key: String
    public var startSec: Double
    public var durationSec: Double
    public var positionCurve: [PositionKeyframe]
    public var volume: Float
    public var loop: Bool
    public var behavior: BehaviorHint
    public var locked: Bool

    public init(label: String, scientific: String?, sourceClipR2Key: String,
                startSec: Double, durationSec: Double,
                positionCurve: [PositionKeyframe],
                volume: Float, loop: Bool, behavior: BehaviorHint,
                locked: Bool) {
        self.id = UUID()
        self.label = label
        self.scientific = scientific
        self.sourceClipR2Key = sourceClipR2Key
        self.startSec = startSec
        self.durationSec = durationSec
        self.positionCurve = positionCurve
        self.volume = volume
        self.loop = loop
        self.behavior = behavior
        self.locked = locked
    }

    public var isAnimated: Bool {
        return positionCurve.count > 1 || behavior == .flyby
    }
}

/// A point in the position curve. Coordinates clamped to [-1, +1] at construction.
public struct PositionKeyframe: Sendable, Equatable {
    public let timeSec: Double
    public let x: Float
    public let y: Float
    public let z: Float

    public init(timeSec: Double, x: Float, y: Float, z: Float) {
        self.timeSec = timeSec
        self.x = max(-1.0, min(1.0, x))
        self.y = max(-1.0, min(1.0, y))
        self.z = max(-1.0, min(1.0, z))
    }
}
