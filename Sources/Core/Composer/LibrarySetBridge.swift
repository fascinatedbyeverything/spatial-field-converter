import Foundation

// ---------------------------------------------------------------------------
// LibrarySetBridge — maps analyzer events from R2CatalogIndex into SetData.
//
// Intentionally model-only (no SwiftUI imports) so the core logic is fully
// testable without spinning up UI.
//
// Two input shapes:
//   • IndexedEvent  — from R2CatalogIndex.allEvents / filtered()
//   • TimelineEvent — from R2CatalogIndex.TimelineData.Event (ScriptView)
//
// Both route through the same internal append path.
// ---------------------------------------------------------------------------

public enum LibrarySetBridge {

    // MARK: - IndexedEvent path (Library search results)

    /// Map an `R2CatalogIndex.IndexedEvent` into a new `SetData.Element` and
    /// append it to `set`. Also ensures the recording's slug appears in
    /// `set.sources`.
    ///
    /// Dedup key: (label, sourceSlug, timeSec rounded to 1 ms) so re-clicking
    /// "Add" on the same row in a search result does not double-add, even after
    /// the set has been saved and reloaded.
    ///
    /// - Returns: `true` if the element was appended; `false` if it was already
    ///   present (duplicate).
    @discardableResult
    public static func add(indexedEvent event: IndexedEventInput,
                            from recordingCategory: String,
                            to set: inout SetData) -> Bool {
        let key = dedupKey(label: event.label,
                           sourceSlug: event.sourceSlug,
                           timeSec: event.startSec)
        guard !set.elements.contains(where: { dedupKey(label: $0.label,
                                                         sourceSlug: $0.sourceSlug,
                                                         timeSec: $0.timeSec) == key }) else {
            return false
        }

        let element = SetData.Element(
            id: UUID().uuidString,
            label: event.label,
            scientific: event.scientific,
            sourceSlug: event.sourceSlug,
            kind: event.scientific != nil ? "species" : "category",
            timeSec: event.startSec,
            durationSec: event.durationSec,
            confidence: event.confidence,
            behaviorHint: BehaviorHint.defaultFor(category: event.label),
            keep: true)

        set.elements.append(element)
        ensureSource(slug: event.sourceSlug,
                     category: recordingCategory,
                     in: &set)
        set.updatedAt = Date()
        return true
    }

    // MARK: - TimelineEvent path (ScriptView)

    /// Map an `R2CatalogIndex.TimelineData.Event` into a `SetData.Element` and
    /// append it to `set`. The `sourceSlug` and `sourceCategory` come from the
    /// enclosing ScriptView.
    ///
    /// - Returns: `true` if the element was appended; `false` if duplicate.
    @discardableResult
    public static func add(timelineEvent event: TimelineEventInput,
                            sourceSlug: String,
                            sourceCategory: String,
                            to set: inout SetData) -> Bool {
        let key = dedupKey(label: event.label,
                           sourceSlug: sourceSlug,
                           timeSec: event.timeSec)
        guard !set.elements.contains(where: { dedupKey(label: $0.label,
                                                         sourceSlug: $0.sourceSlug,
                                                         timeSec: $0.timeSec) == key }) else {
            return false
        }

        let element = SetData.Element(
            id: UUID().uuidString,
            label: event.label,
            scientific: event.scientific,
            sourceSlug: sourceSlug,
            kind: event.kind,
            timeSec: event.timeSec,
            durationSec: event.durationSec,
            confidence: event.confidence,
            behaviorHint: BehaviorHint.defaultFor(category: event.label),
            keep: true)

        set.elements.append(element)
        ensureSource(slug: sourceSlug, category: sourceCategory, in: &set)
        set.updatedAt = Date()
        return true
    }

    // MARK: - Bulk add

    /// Append all events in `events` that are not already in `set`.
    /// - Returns: Count of newly appended elements.
    @discardableResult
    public static func addAll(indexedEvents events: [IndexedEventInput],
                               recordingCategory: String,
                               to set: inout SetData) -> Int {
        var added = 0
        for event in events {
            if add(indexedEvent: event,
                   from: recordingCategory,
                   to: &set) {
                added += 1
            }
        }
        return added
    }

    // MARK: - Membership check

    /// `true` when an IndexedEvent's dedup key is already present in `set`.
    public static func contains(indexedEvent event: IndexedEventInput,
                                 in set: SetData) -> Bool {
        let key = dedupKey(label: event.label,
                           sourceSlug: event.sourceSlug,
                           timeSec: event.startSec)
        return set.elements.contains(where: {
            dedupKey(label: $0.label,
                     sourceSlug: $0.sourceSlug,
                     timeSec: $0.timeSec) == key
        })
    }

    /// `true` when a TimelineEvent's dedup key is already present in `set`.
    public static func contains(timelineEvent event: TimelineEventInput,
                                 sourceSlug: String,
                                 in set: SetData) -> Bool {
        let key = dedupKey(label: event.label,
                           sourceSlug: sourceSlug,
                           timeSec: event.timeSec)
        return set.elements.contains(where: {
            dedupKey(label: $0.label,
                     sourceSlug: $0.sourceSlug,
                     timeSec: $0.timeSec) == key
        })
    }

    // MARK: - Private helpers

    /// Append `SetData.Source(slug:category:)` if slug not already present.
    private static func ensureSource(slug: String,
                                      category: String,
                                      in set: inout SetData) {
        guard !set.sources.contains(where: { $0.slug == slug }) else { return }
        set.sources.append(SetData.Source(slug: slug, category: category))
    }

    /// Stable string key for dedup. Rounds timeSec to 3 decimal places (1 ms
    /// precision) to survive JSON encode/decode round-trips.
    private static func dedupKey(label: String,
                                  sourceSlug: String,
                                  timeSec: Double) -> String {
        let rounded = (timeSec * 1000).rounded() / 1000
        return "\(sourceSlug)|\(label)|\(rounded)"
    }
}

// ---------------------------------------------------------------------------
// Input value types — thin protocol-compatible structs that let the bridge
// accept either real index types or test fakes without importing SwiftUI.
// ---------------------------------------------------------------------------

/// Subset of `R2CatalogIndex.IndexedEvent` fields the bridge needs.
public struct IndexedEventInput: Sendable {
    public let sourceSlug: String
    public let sourceCategory: String
    public let startSec: Double
    public let durationSec: Double
    public let label: String
    public let scientific: String?
    public let confidence: Double

    public init(sourceSlug: String,
                sourceCategory: String,
                startSec: Double,
                durationSec: Double,
                label: String,
                scientific: String?,
                confidence: Double) {
        self.sourceSlug = sourceSlug
        self.sourceCategory = sourceCategory
        self.startSec = startSec
        self.durationSec = durationSec
        self.label = label
        self.scientific = scientific
        self.confidence = confidence
    }
}

/// Subset of `R2CatalogIndex.TimelineData.Event` fields the bridge needs.
public struct TimelineEventInput: Sendable {
    public let timeSec: Double
    public let kind: String
    public let label: String
    public let scientific: String?
    public let confidence: Double
    public let durationSec: Double

    public init(timeSec: Double,
                kind: String,
                label: String,
                scientific: String?,
                confidence: Double,
                durationSec: Double) {
        self.timeSec = timeSec
        self.kind = kind
        self.label = label
        self.scientific = scientific
        self.confidence = confidence
        self.durationSec = durationSec
    }
}
