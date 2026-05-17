import XCTest
@testable import SpatialFieldConverter

// ---------------------------------------------------------------------------
// LibrarySetBridgeTests — exercises dedup, append, bulk-add, and membership.
// No SwiftUI, no network, no disk.
// ---------------------------------------------------------------------------

final class LibrarySetBridgeTests: XCTestCase {

    // MARK: - Fixtures

    private func emptySet() -> SetData {
        SetData(name: "Test", slug: "test",
                createdAt: Date(timeIntervalSince1970: 0),
                updatedAt: Date(timeIntervalSince1970: 0),
                sources: [], elements: [])
    }

    private func cardinalEvent(startSec: Double = 10.0) -> IndexedEventInput {
        IndexedEventInput(
            sourceSlug: "recording-abc",
            sourceCategory: "zoom-bounces",
            startSec: startSec,
            durationSec: 3.0,
            label: "Northern Cardinal",
            scientific: "Cardinalis cardinalis",
            confidence: 0.92)
    }

    private func windEvent() -> IndexedEventInput {
        IndexedEventInput(
            sourceSlug: "recording-abc",
            sourceCategory: "zoom-bounces",
            startSec: 45.0,
            durationSec: 12.0,
            label: "wind",
            scientific: nil,
            confidence: 0.78)
    }

    private func timelineCardinal(timeSec: Double = 10.0) -> TimelineEventInput {
        TimelineEventInput(
            timeSec: timeSec,
            kind: "species",
            label: "Northern Cardinal",
            scientific: "Cardinalis cardinalis",
            confidence: 0.92,
            durationSec: 3.0)
    }

    // MARK: - IndexedEvent: basic append

    func test_addIndexedEvent_appendsElement() {
        var set = emptySet()
        let added = LibrarySetBridge.add(indexedEvent: cardinalEvent(),
                                          from: "zoom-bounces",
                                          to: &set)
        XCTAssertTrue(added)
        XCTAssertEqual(set.elements.count, 1)
        XCTAssertEqual(set.elements[0].label, "Northern Cardinal")
        XCTAssertEqual(set.elements[0].scientific, "Cardinalis cardinalis")
        XCTAssertEqual(set.elements[0].sourceSlug, "recording-abc")
        XCTAssertEqual(set.elements[0].kind, "species")
        XCTAssertEqual(set.elements[0].timeSec, 10.0)
        XCTAssertEqual(set.elements[0].confidence, 0.92)
        XCTAssertTrue(set.elements[0].keep)
    }

    func test_addIndexedEvent_withNoScientific_kindIsCategory() {
        var set = emptySet()
        LibrarySetBridge.add(indexedEvent: windEvent(), from: "zoom-bounces", to: &set)
        XCTAssertEqual(set.elements[0].kind, "category")
    }

    // MARK: - IndexedEvent: dedup

    func test_addIndexedEvent_deduplicatesOnSameLabelSourceTime() {
        var set = emptySet()
        let first = LibrarySetBridge.add(indexedEvent: cardinalEvent(),
                                          from: "zoom-bounces", to: &set)
        let second = LibrarySetBridge.add(indexedEvent: cardinalEvent(),
                                           from: "zoom-bounces", to: &set)
        XCTAssertTrue(first)
        XCTAssertFalse(second)
        XCTAssertEqual(set.elements.count, 1)
    }

    func test_addIndexedEvent_differentStartSecIsNotDuplicate() {
        var set = emptySet()
        LibrarySetBridge.add(indexedEvent: cardinalEvent(startSec: 10.0),
                              from: "zoom-bounces", to: &set)
        let added = LibrarySetBridge.add(indexedEvent: cardinalEvent(startSec: 20.0),
                                          from: "zoom-bounces", to: &set)
        XCTAssertTrue(added)
        XCTAssertEqual(set.elements.count, 2)
    }

    func test_addIndexedEvent_differentSourceSlugIsNotDuplicate() {
        var set = emptySet()
        let e1 = IndexedEventInput(
            sourceSlug: "recording-001",
            sourceCategory: "zoom-bounces",
            startSec: 10.0, durationSec: 3.0,
            label: "Northern Cardinal", scientific: "Cardinalis cardinalis",
            confidence: 0.9)
        let e2 = IndexedEventInput(
            sourceSlug: "recording-002",
            sourceCategory: "zoom-bounces",
            startSec: 10.0, durationSec: 3.0,
            label: "Northern Cardinal", scientific: "Cardinalis cardinalis",
            confidence: 0.9)
        LibrarySetBridge.add(indexedEvent: e1, from: "zoom-bounces", to: &set)
        let added = LibrarySetBridge.add(indexedEvent: e2, from: "zoom-bounces", to: &set)
        XCTAssertTrue(added)
        XCTAssertEqual(set.elements.count, 2)
    }

    // MARK: - Sources dedup

    func test_addIndexedEvent_addsSourceEntry() {
        var set = emptySet()
        LibrarySetBridge.add(indexedEvent: cardinalEvent(), from: "zoom-bounces", to: &set)
        XCTAssertEqual(set.sources.count, 1)
        XCTAssertEqual(set.sources[0].slug, "recording-abc")
        XCTAssertEqual(set.sources[0].category, "zoom-bounces")
    }

    func test_addIndexedEvent_deduplicatesSourcesOnSlug() {
        var set = emptySet()
        LibrarySetBridge.add(indexedEvent: cardinalEvent(), from: "zoom-bounces", to: &set)
        LibrarySetBridge.add(indexedEvent: windEvent(), from: "zoom-bounces", to: &set)
        XCTAssertEqual(set.sources.count, 1, "Same slug from different events must yield one source entry")
    }

    func test_addIndexedEvent_addsTwoSourcesForTwoSlugs() {
        var set = emptySet()
        let e1 = IndexedEventInput(
            sourceSlug: "slug-a", sourceCategory: "zoom-bounces",
            startSec: 5.0, durationSec: 2.0,
            label: "Wind", scientific: nil, confidence: 0.7)
        let e2 = IndexedEventInput(
            sourceSlug: "slug-b", sourceCategory: "zylia-bounces",
            startSec: 8.0, durationSec: 2.0,
            label: "Rain", scientific: nil, confidence: 0.8)
        LibrarySetBridge.add(indexedEvent: e1, from: "zoom-bounces", to: &set)
        LibrarySetBridge.add(indexedEvent: e2, from: "zylia-bounces", to: &set)
        XCTAssertEqual(set.sources.count, 2)
    }

    // MARK: - TimelineEvent path

    func test_addTimelineEvent_appendsElement() {
        var set = emptySet()
        let added = LibrarySetBridge.add(
            timelineEvent: timelineCardinal(),
            sourceSlug: "recording-abc",
            sourceCategory: "zoom-bounces",
            to: &set)
        XCTAssertTrue(added)
        XCTAssertEqual(set.elements.count, 1)
        XCTAssertEqual(set.elements[0].label, "Northern Cardinal")
        XCTAssertEqual(set.elements[0].kind, "species")
        XCTAssertEqual(set.elements[0].timeSec, 10.0)
    }

    func test_addTimelineEvent_deduplicates() {
        var set = emptySet()
        LibrarySetBridge.add(timelineEvent: timelineCardinal(),
                              sourceSlug: "recording-abc",
                              sourceCategory: "zoom-bounces",
                              to: &set)
        let second = LibrarySetBridge.add(
            timelineEvent: timelineCardinal(),
            sourceSlug: "recording-abc",
            sourceCategory: "zoom-bounces",
            to: &set)
        XCTAssertFalse(second)
        XCTAssertEqual(set.elements.count, 1)
    }

    func test_addTimelineEvent_addsSourceEntry() {
        var set = emptySet()
        LibrarySetBridge.add(timelineEvent: timelineCardinal(),
                              sourceSlug: "recording-abc",
                              sourceCategory: "zoom-bounces",
                              to: &set)
        XCTAssertEqual(set.sources.count, 1)
        XCTAssertEqual(set.sources[0].slug, "recording-abc")
    }

    // MARK: - Bulk add

    func test_addAll_appendsAllEvents() {
        var set = emptySet()
        let events = [cardinalEvent(), windEvent()]
        let count = LibrarySetBridge.addAll(indexedEvents: events,
                                             recordingCategory: "zoom-bounces",
                                             to: &set)
        XCTAssertEqual(count, 2)
        XCTAssertEqual(set.elements.count, 2)
    }

    func test_addAll_skipsAlreadyPresentEvents() {
        var set = emptySet()
        // Pre-add the cardinal.
        LibrarySetBridge.add(indexedEvent: cardinalEvent(), from: "zoom-bounces", to: &set)
        let events = [cardinalEvent(), windEvent()]
        let count = LibrarySetBridge.addAll(indexedEvents: events,
                                             recordingCategory: "zoom-bounces",
                                             to: &set)
        XCTAssertEqual(count, 1, "Only wind should be newly added")
        XCTAssertEqual(set.elements.count, 2)
    }

    func test_addAll_emptyListAddsZero() {
        var set = emptySet()
        let count = LibrarySetBridge.addAll(indexedEvents: [],
                                             recordingCategory: "zoom-bounces",
                                             to: &set)
        XCTAssertEqual(count, 0)
        XCTAssertEqual(set.elements.count, 0)
    }

    // MARK: - Membership check

    func test_containsIndexedEvent_falseOnEmpty() {
        let set = emptySet()
        XCTAssertFalse(LibrarySetBridge.contains(indexedEvent: cardinalEvent(), in: set))
    }

    func test_containsIndexedEvent_trueAfterAdd() {
        var set = emptySet()
        LibrarySetBridge.add(indexedEvent: cardinalEvent(), from: "zoom-bounces", to: &set)
        XCTAssertTrue(LibrarySetBridge.contains(indexedEvent: cardinalEvent(), in: set))
    }

    func test_containsTimelineEvent_trueAfterAdd() {
        var set = emptySet()
        LibrarySetBridge.add(timelineEvent: timelineCardinal(),
                              sourceSlug: "recording-abc",
                              sourceCategory: "zoom-bounces",
                              to: &set)
        XCTAssertTrue(LibrarySetBridge.contains(
            timelineEvent: timelineCardinal(),
            sourceSlug: "recording-abc",
            in: set))
    }

    // MARK: - BehaviorHint mapping

    func test_addIndexedEvent_windGetssSustainedBehavior() {
        var set = emptySet()
        LibrarySetBridge.add(indexedEvent: windEvent(), from: "zoom-bounces", to: &set)
        XCTAssertEqual(set.elements[0].behaviorHint, .sustained)
    }

    func test_addIndexedEvent_birdGetsDiscreteBehavior() {
        var set = emptySet()
        LibrarySetBridge.add(indexedEvent: cardinalEvent(), from: "zoom-bounces", to: &set)
        XCTAssertEqual(set.elements[0].behaviorHint, .discrete)
    }

    // MARK: - updatedAt mutation

    func test_add_stampsUpdatedAt() {
        var set = emptySet()    // updatedAt = epoch 0
        let before = Date()
        LibrarySetBridge.add(indexedEvent: cardinalEvent(), from: "zoom-bounces", to: &set)
        XCTAssertGreaterThanOrEqual(set.updatedAt.timeIntervalSince1970,
                                     before.timeIntervalSince1970)
    }

    func test_addDuplicate_doesNotMutateUpdatedAt() {
        var set = emptySet()
        LibrarySetBridge.add(indexedEvent: cardinalEvent(), from: "zoom-bounces", to: &set)
        let afterFirst = set.updatedAt
        // Brief sleep so clock moves
        Thread.sleep(forTimeInterval: 0.01)
        LibrarySetBridge.add(indexedEvent: cardinalEvent(), from: "zoom-bounces", to: &set)
        XCTAssertEqual(set.updatedAt, afterFirst, "Duplicate add must not update timestamp")
    }
}
