import Foundation

enum Suit: String, CaseIterable, Codable, Identifiable {
    case spade = "♠"
    case heart = "♥"
    case club = "♣"
    case diamond = "♦"

    var id: String { rawValue }
    var isRed: Bool { self == .heart || self == .diamond }
}

/// 牌组没有 3、4 和大小王，所以只有 11 个点数。
enum Rank: String, CaseIterable, Codable, Identifiable {
    case two = "2"
    case ace = "A"
    case king = "K"
    case queen = "Q"
    case jack = "J"
    case ten = "10"
    case nine = "9"
    case eight = "8"
    case seven = "7"
    case six = "6"
    case five = "5"

    var id: String { rawValue }
}

struct Card: Hashable, Codable {
    let suit: Suit
    let rank: Rank

    var label: String { suit.rawValue + rank.rawValue }
}

enum Seat: String, CaseIterable, Codable, Identifiable {
    case me = "我"
    case left = "上家"
    case across = "对家"
    case right = "下家"

    var id: String { rawValue }
}

/// 一张已见的牌，以及它属于哪一家。
struct SeenCard: Hashable, Codable {
    let card: Card
    let seat: Seat
}

enum PlayerCount: Int, CaseIterable, Codable, Identifiable {
    case three = 3
    case four = 4

    var id: Int { rawValue }
    var bottomCount: Int { GameTracker.totalCards - rawValue * GameTracker.handSize }
    var seats: [Seat] { self == .three ? [.me, .left, .right] : [.me, .left, .across, .right] }
}

/// 记牌核心：history 按时间记录每一张已见的牌，其余数字都由它算出。
struct GameTracker: Codable, Equatable {
    static let copiesPerCard = 4
    static let totalCards = Suit.allCases.count * Rank.allCases.count * copiesPerCard
    static let handSize = 44

    var playerCount: PlayerCount = .four
    private(set) var history: [SeenCard] = []

    var seenTotal: Int { history.count }
    var remainingTotal: Int { Self.totalCards - history.count }

    func remaining(_ card: Card) -> Int {
        Self.copiesPerCard - history.filter { $0.card == card }.count
    }

    /// 这一家记过的牌，按 2 到 5 的点数顺序排列。
    func cards(of seat: Seat) -> [Card] {
        Rank.allCases.flatMap { rank in
            history.filter { $0.seat == seat && $0.card.rank == rank }.map(\.card)
        }
    }

    func count(of rank: Rank, by seat: Seat) -> Int {
        history.filter { $0.seat == seat && $0.card.rank == rank }.count
    }

    func remaining(rank: Rank) -> Int {
        Suit.allCases.reduce(0) { $0 + remaining(Card(suit: $1, rank: rank)) }
    }

    func remaining(suit: Suit) -> Int {
        Rank.allCases.reduce(0) { $0 + remaining(Card(suit: suit, rank: $1)) }
    }

    /// 这种牌已经见满 4 张时返回 false，说明录入或识别有误。
    @discardableResult
    mutating func record(_ card: Card, by seat: Seat = .me) -> Bool {
        guard remaining(card) > 0 else { return false }
        history.append(SeenCard(card: card, seat: seat))
        return true
    }

    /// 撤销最近一次记录。
    @discardableResult
    mutating func undo() -> SeenCard? {
        history.popLast()
    }

    /// 还原指定的牌，用于修正记错的某一张。
    @discardableResult
    mutating func restore(_ card: Card) -> Bool {
        guard let index = history.lastIndex(where: { $0.card == card }) else { return false }
        history.remove(at: index)
        return true
    }

    mutating func reset() {
        history.removeAll()
    }
}
