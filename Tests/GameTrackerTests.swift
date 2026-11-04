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
        XCTAssertEqual(tracker.undo()?.card, heartTwo)
        XCTAssertEqual(tracker.history.map(\.card), [spadeAce])
    }

    func testRestoreSpecificCard() {
        var tracker = GameTracker()
        let heartTwo = Card(suit: .heart, rank: .two)
        tracker.record(spadeAce)
        tracker.record(heartTwo)
        XCTAssertTrue(tracker.restore(spadeAce))
        XCTAssertEqual(tracker.history.map(\.card), [heartTwo])
        XCTAssertFalse(tracker.restore(spadeAce))
    }

    func testCardsAreGroupedBySeat() {
        var tracker = GameTracker()
        let heartTwo = Card(suit: .heart, rank: .two)
        tracker.record(spadeAce, by: .upper)
        tracker.record(heartTwo, by: .lower)
        XCTAssertEqual(tracker.cards(of: .upper), [spadeAce])
        XCTAssertEqual(tracker.cards(of: .lower), [heartTwo])
        XCTAssertEqual(tracker.cards(of: .me), [])
    }

    func testSeatCardsFollowRankOrderAndCount() {
        var tracker = GameTracker()
        let heartFive = Card(suit: .heart, rank: .five)
        let clubTwo = Card(suit: .club, rank: .two)
        tracker.record(heartFive, by: .upper)
        tracker.record(spadeAce, by: .upper)
        tracker.record(clubTwo, by: .upper)
        tracker.record(clubTwo, by: .upper)
        XCTAssertEqual(tracker.cards(of: .upper), [clubTwo, clubTwo, spadeAce, heartFive])
        XCTAssertEqual(tracker.count(of: .two, by: .upper), 2)
        XCTAssertEqual(tracker.count(of: .two, by: .lower), 0)
    }

    func testEventStoreReturnsOnlyNewEvents() throws {
        let store = BroadcastEventStore(backend: MemoryBackend())
        let seen = SeenCard(card: spadeAce, seat: .upper)
        store.append([seen, seen])
        XCTAssertEqual(store.events(after: 0).map(\.seq), [1, 2])
        XCTAssertEqual(store.events(after: 1).map(\.seq), [2])
    }

    func testHeartbeatRoundTrips() {
        let store = BroadcastEventStore(backend: MemoryBackend())
        let now = Date()
        XCTAssertFalse(store.isBroadcasting(at: now))
        store.beat(at: now)
        XCTAssertTrue(store.isBroadcasting(at: now.addingTimeInterval(1)))
        XCTAssertFalse(store.isBroadcasting(at: now.addingTimeInterval(5)))
    }
}

/// 测试用的内存后端，替代真机上的 keychain。
private final class MemoryBackend: BroadcastBackend {
    private var storage: [String: Data] = [:]
    func data(forKey key: String) -> Data? { storage[key] }
    func set(_ data: Data, forKey key: String) { storage[key] = data }
}
