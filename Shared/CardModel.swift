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
    case two = "2"

    var id: String { rawValue }
}

struct Card: Hashable, Codable {
    let suit: Suit
    let rank: Rank
}

enum PlayerCount: Int, CaseIterable, Codable, Identifiable {
    case three = 3
    case four = 4

    var id: Int { rawValue }
    var bottomCount: Int { GameTracker.totalCards - rawValue * GameTracker.handSize }
}

/// 记牌核心：history 按时间记录每一张已见的牌，其余数字都由它算出。
struct GameTracker: Codable, Equatable {
    static let copiesPerCard = 4
    static let totalCards = Suit.allCases.count * Rank.allCases.count * copiesPerCard
    static let handSize = 44

    var playerCount: PlayerCount = .four
    private(set) var history: [Card] = []

    var seenTotal: Int { history.count }
    var remainingTotal: Int { Self.totalCards - history.count }

    func remaining(_ card: Card) -> Int {
        Self.copiesPerCard - history.filter { $0 == card }.count
    }

    func remaining(rank: Rank) -> Int {
        Suit.allCases.reduce(0) { $0 + remaining(Card(suit: $1, rank: rank)) }
    }

    func remaining(suit: Suit) -> Int {
        Rank.allCases.reduce(0) { $0 + remaining(Card(suit: suit, rank: $1)) }
    }

    /// 这种牌已经见满 4 张时返回 false，说明录入或识别有误。
    @discardableResult
    mutating func record(_ card: Card) -> Bool {
        guard remaining(card) > 0 else { return false }
        history.append(card)
        return true
    }

    /// 撤销最近一次记录。
    @discardableResult
    mutating func undo() -> Card? {
        history.popLast()
    }

    /// 还原指定的牌，用于修正记错的某一张。
    @discardableResult
    mutating func restore(_ card: Card) -> Bool {
        guard let index = history.lastIndex(of: card) else { return false }
        history.remove(at: index)
        return true
    }

    mutating func reset() {
        history.removeAll()
    }
}
