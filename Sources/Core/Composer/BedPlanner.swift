import Foundation

public enum BedPlanner {

    /// Stitch sustained elements from `set` into a bed that covers at least `targetDurationSec`.
    /// Elements are cycled in descending duration order. Returns an empty plan when no sustained
    /// elements are marked `keep`.
    public static func plan(set: SetData, targetDurationSec: Double, crossfadeMs: Int) -> BedPlan {
        let sustained = set.keptElements.filter { $0.behaviorHint == .sustained }
        guard !sustained.isEmpty else {
            return BedPlan(segments: [], crossfadeMs: crossfadeMs)
        }

        // Longest clips first so we minimise segment count.
        let ordered = sustained.sorted { $0.durationSec > $1.durationSec }

        var segments: [BedSegment] = []
        var covered: Double = 0
        var i = 0

        while covered < targetDurationSec {
            let element = ordered[i % ordered.count]
            guard let source = set.sources.first(where: { $0.slug == element.sourceSlug }) else {
                i += 1
                // Safety valve — skip unresolvable sources but don't infinite-loop.
                if i > ordered.count * 2 { break }
                continue
            }
            let r2Key = "stems/spatial-mix/field-recording/\(source.category)/\(source.slug)/bed.m4a"
            segments.append(BedSegment(
                sourceClipR2Key: r2Key,
                startInClipSec: element.timeSec,
                endInClipSec: element.timeSec + element.durationSec
            ))
            covered += element.durationSec
            i += 1
            if i > 1000 { break }
        }

        return BedPlan(segments: segments, crossfadeMs: crossfadeMs)
    }
}
