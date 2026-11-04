import XCTest
@testable import CardCounter

final class GameTrackerTests: XCTestCase {
    private let spadeAce = Card(suit: .spade, rank: .ace)

    func testDeckAndBottomCounts() {
        XCTAssertEqual(GameTracker.totalCards, 176)
        XCTAssertEqual(PlayerCount.three.bottomCount, 44)
        XCTAssertEqual(PlayerCount.four.bottomCount, 0)
    }

    func testRecordStopsAtFourCopies() {
        var tracker = GameTracker()
        for _ in 0..<4 { XCTAssertTrue(tracker.record(spadeAce)) }
        XCTAssertFalse(tracker.record(spadeAce))
        XCTAssertEqual(tracker.remaining(spadeAce), 0)
        XCTAssertEqual(tracker.seenTotal, 4)
    }

    func testRemainingBySuitAndRank() {
        var tracker = GameTracker()
        tracker.record(spadeAce)
        XCTAssertEqual(tracker.remaining(suit: .spade), 43)
        XCTAssertEqual(tracker.remaining(rank: .ace), 15)
        XCTAssertEqual(tracker.remaining(suit: .heart), 44)
    }

    func testUndoRemovesLatestCard() {
        var tracker = GameTracker()
        let heartTwo = Card(suit: .heart, rank: .two)
        tracker.record(spadeAce)
        tracker.record(heartTwo)
        XCTAssertEqual(tracker.undo(), heartTwo)
        XCTAssertEqual(tracker.history, [spadeAce])
    }

    func testRestoreSpecificCard() {
        var tracker = GameTracker()
        let heartTwo = Card(suit: .heart, rank: .two)
        tracker.record(spadeAce)
        tracker.record(heartTwo)
        XCTAssertTrue(tracker.restore(spadeAce))
        XCTAssertEqual(tracker.history, [heartTwo])
        XCTAssertFalse(tracker.restore(spadeAce))
    }

    func testEventStoreReturnsOnlyNewEvents() throws {
        let suite = "GameTrackerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = BroadcastEventStore(defaults: defaults)
        store.append([spadeAce, spadeAce])
        XCTAssertEqual(store.events(after: 0).map(\.seq), [1, 2])
        XCTAssertEqual(store.events(after: 1).map(\.seq), [2])
    }
}
