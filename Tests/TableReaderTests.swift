import UIKit
import XCTest
@testable import CardCounter

/// 测试画面取自实战录屏，只保留出牌区。
final class TableReaderTests: XCTestCase {
    private func loadFrame(_ name: String) throws -> TableFrame {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "jpg"))
        let image = try XCTUnwrap(UIImage(contentsOfFile: url.path)?.cgImage)
        let width = image.width
        var rgba = [UInt8](repeating: 0, count: width * image.height * 4)
        rgba.withUnsafeMutableBytes { buffer in
            let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            )
            context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: image.height))
        }
        return TableFrame(rgba: rgba, width: width)
    }

    private func labels(_ cards: [SeenCard]) -> [String] {
        cards.map(\.card.label)
    }

    func testReadsFiveCardsFromLowerSeat() throws {
        let reader = TableReader()
        let frame = try loadFrame("left")
        XCTAssertEqual(reader.read(frame), [], "同一读数要连续出现两次")

        let cards = reader.read(frame)
        XCTAssertEqual(labels(cards), ["♠9", "♣9", "♣9", "♦9", "♦9"])
        XCTAssertTrue(cards.allSatisfy { $0.seat == .lower })
        XCTAssertTrue(reader.hasReadCards)
    }

    func testReadsFourCardsFromUpperSeat() throws {
        let reader = TableReader()
        let frame = try loadFrame("right")
        _ = reader.read(frame)

        let cards = reader.read(frame)
        XCTAssertEqual(labels(cards), ["♠7", "♥7", "♥7", "♣7"])
        XCTAssertTrue(cards.allSatisfy { $0.seat == .upper })
    }

    func testReadsSixCardsFromMyPlay() throws {
        let reader = TableReader()
        let frame = try loadFrame("center")
        _ = reader.read(frame)

        let cards = reader.read(frame)
        XCTAssertEqual(labels(cards), ["♠2", "♥2", "♥2", "♣2", "♦2", "♦2"])
        XCTAssertTrue(cards.allSatisfy { $0.seat == .me })
    }

    func testSamePlayIsCountedOnce() throws {
        let reader = TableReader()
        let frame = try loadFrame("left")
        _ = reader.read(frame)
        _ = reader.read(frame)
        XCTAssertEqual(reader.read(frame), [])
    }
}
