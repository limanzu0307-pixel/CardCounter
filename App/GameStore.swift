import Foundation

@MainActor
final class GameStore: ObservableObject {
    @Published private(set) var tracker: GameTracker
    @Published private(set) var isBroadcasting = false
    /// 识别出的牌已经见满 4 张的次数，不为 0 时说明需要人工核对。
    @Published private(set) var rejectedCount = 0

    private enum Key {
        static let tracker = "game.tracker"
        static let lastSeq = "game.lastSeq"
    }

    private let defaults = UserDefaults.standard
    private let events = BroadcastEventStore()
    private var lastSeq: Int
    private var timer: Timer?

    init() {
        if let data = defaults.data(forKey: Key.tracker),
           let saved = try? JSONDecoder().decode(GameTracker.self, from: data) {
            tracker = saved
        } else {
            tracker = GameTracker()
        }
        lastSeq = defaults.integer(forKey: Key.lastSeq)

        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.syncBroadcast() }
        }
    }

    func setPlayerCount(_ count: PlayerCount) {
        tracker.playerCount = count
        save()
    }

    func record(_ card: Card, by seat: Seat) {
        guard tracker.record(card, by: seat) else { return }
        save()
    }

    func restore(_ card: Card) {
        guard tracker.restore(card) else { return }
        save()
    }

    func undo() {
        guard tracker.undo() != nil else { return }
        save()
    }

    func reset() {
        tracker.reset()
        rejectedCount = 0
        // 上一局还没读取的事件不能带进新的一局
        lastSeq = events.events(after: lastSeq).last?.seq ?? lastSeq
        save()
    }

    private func syncBroadcast() {
        isBroadcasting = events.isBroadcasting()

        let newEvents = events.events(after: lastSeq)
        guard let last = newEvents.last else { return }
        for event in newEvents {
            if !tracker.record(event.seen.card, by: event.seen.seat) {
                rejectedCount += 1
            }
        }
        lastSeq = last.seq
        save()
    }

    private func save() {
        defaults.set(try? JSONEncoder().encode(tracker), forKey: Key.tracker)
        defaults.set(lastSeq, forKey: Key.lastSeq)
    }
}
