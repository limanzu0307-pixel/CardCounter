import Foundation

struct CardEvent: Codable {
    let seq: Int
    let seen: SeenCard
}

/// 广播扩展和主 APP 是两个进程，通过 App Group 传递识别结果。
/// 只有扩展写入事件，主 APP 按序号读取，所以两边不会互相覆盖。
final class BroadcastEventStore {
    static let groupID = "group.app.cardcounter"

    private enum Key {
        static let events = "broadcast.events"
        static let heartbeat = "broadcast.heartbeat"
    }

    private let maxStoredEvents = 500
    private let defaults: UserDefaults?

    init(defaults: UserDefaults? = UserDefaults(suiteName: BroadcastEventStore.groupID)) {
        self.defaults = defaults
    }

    func append(_ cards: [SeenCard]) {
        guard !cards.isEmpty else { return }
        var events = allEvents()
        var seq = events.last?.seq ?? 0
        for seen in cards {
            seq += 1
            events.append(CardEvent(seq: seq, seen: seen))
        }
        let trimmed = Array(events.suffix(maxStoredEvents))
        defaults?.set(try? JSONEncoder().encode(trimmed), forKey: Key.events)
    }

    func events(after seq: Int) -> [CardEvent] {
        allEvents().filter { $0.seq > seq }
    }

    func beat(at date: Date = Date()) {
        defaults?.set(date.timeIntervalSince1970, forKey: Key.heartbeat)
    }

    func isBroadcasting(at date: Date = Date()) -> Bool {
        guard let last = defaults?.double(forKey: Key.heartbeat), last > 0 else { return false }
        return date.timeIntervalSince1970 - last < 3
    }

    private func allEvents() -> [CardEvent] {
        guard let data = defaults?.data(forKey: Key.events) else { return [] }
        return (try? JSONDecoder().decode([CardEvent].self, from: data)) ?? []
    }
}
