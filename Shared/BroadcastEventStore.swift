import Foundation

struct CardEvent: Codable {
    let seq: Int
    let seen: SeenCard
}

/// 广播扩展和主 APP 是两个进程，通过 keychain 共享组传递识别结果。
/// 只有扩展写入事件，主 APP 按序号读取，所以两边不会互相覆盖。
final class BroadcastEventStore {
    private enum Key {
        static let events = "broadcast.events"
        static let heartbeat = "broadcast.heartbeat"
    }

    private let maxStoredEvents = 500
    private let backend: BroadcastBackend

    init(backend: BroadcastBackend = KeychainBackend()) {
        self.backend = backend
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
        if let data = try? JSONEncoder().encode(trimmed) {
            backend.set(data, forKey: Key.events)
        }
    }

    func events(after seq: Int) -> [CardEvent] {
        allEvents().filter { $0.seq > seq }
    }

    func beat(at date: Date = Date()) {
        var value = date.timeIntervalSince1970
        let data = Data(bytes: &value, count: MemoryLayout<Double>.size)
        backend.set(data, forKey: Key.heartbeat)
    }

    func isBroadcasting(at date: Date = Date()) -> Bool {
        guard let data = backend.data(forKey: Key.heartbeat), data.count == MemoryLayout<Double>.size else { return false }
        let last = data.withUnsafeBytes { $0.load(as: Double.self) }
        return last > 0 && date.timeIntervalSince1970 - last < 3
    }

    private func allEvents() -> [CardEvent] {
        guard let data = backend.data(forKey: Key.events) else { return [] }
        return (try? JSONDecoder().decode([CardEvent].self, from: data)) ?? []
    }
}
