import CoreVideo
import ImageIO

/// 皮皮打筒子 3 人局的出牌区。坐标按 2622×1206 的横屏画面标定。
enum TableArea: CaseIterable {
    case left
    case right
    case center

    var x0: Int { [TableArea.left: 440, .right: 1600, .center: 900][self]! }
    var x1: Int { [TableArea.left: 1000, .right: 2190, .center: 1740][self]! }
    var y0: Int { self == .center ? 500 : 340 }
    var y1: Int { self == .center ? 690 : 530 }
    var cardTop: Int { self == .center ? 510 : 350 }

    /// 出牌顺序是 我 → 左边 → 右边，所以左边是下家、右边是上家。
    var seat: Seat {
        switch self {
        case .left: return .lower
        case .right: return .upper
        case .center: return .me
        }
    }
}

/// 一块出牌区的亮度和色度数据。
struct TableRegion {
    let area: TableArea
    let width: Int
    let height: Int
    var luma: [UInt8]
    var cb: [UInt8]
    var cr: [UInt8]

    init(area: TableArea) {
        self.area = area
        width = area.x1 - area.x0
        height = area.y1 - area.y0
        luma = [UInt8](repeating: 0, count: width * height)
        cb = [UInt8](repeating: 128, count: width * height)
        cr = [UInt8](repeating: 128, count: width * height)
    }
}

struct TableFrame {
    static let width = 2622
    static let height = 1206

    let regions: [TableRegion]

    /// 从屏幕广播的 YCbCr 画面取出三块出牌区。
    init?(pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) {
        let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
        let fullRange = format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        guard fullRange || format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let lumaBase = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0),
              let chromaBase = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1) else { return nil }

        let lumaPlane = lumaBase.assumingMemoryBound(to: UInt8.self)
        let chromaPlane = chromaBase.assumingMemoryBound(to: UInt8.self)
        let lumaStride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        let chromaStride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)
        let bufferWidth = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let bufferHeight = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)

        let rotated = orientation == .left || orientation == .right
        let displayWidth = rotated ? bufferHeight : bufferWidth
        let displayHeight = rotated ? bufferWidth : bufferHeight
        guard displayWidth > displayHeight else { return nil }

        let scaleX = Double(displayWidth) / Double(Self.width)
        let scaleY = Double(displayHeight) / Double(Self.height)

        regions = TableArea.allCases.map { area in
            var region = TableRegion(area: area)
            for row in 0..<region.height {
                let displayY = Int(Double(area.y0 + row) * scaleY)
                for column in 0..<region.width {
                    let displayX = Int(Double(area.x0 + column) * scaleX)
                    let bufferX: Int
                    let bufferY: Int
                    switch orientation {
                    case .down:
                        bufferX = bufferWidth - 1 - displayX
                        bufferY = bufferHeight - 1 - displayY
                    case .right:
                        bufferX = displayY
                        bufferY = bufferHeight - 1 - displayX
                    case .left:
                        bufferX = bufferWidth - 1 - displayY
                        bufferY = displayX
                    default:
                        bufferX = displayX
                        bufferY = displayY
                    }
                    let index = row * region.width + column
                    let luma = lumaPlane[bufferY * lumaStride + bufferX]
                    region.luma[index] = fullRange ? luma : Self.expand(luma)
                    let chroma = bufferY / 2 * chromaStride + bufferX / 2 * 2
                    region.cb[index] = chromaPlane[chroma]
                    region.cr[index] = chromaPlane[chroma + 1]
                }
            }
            return region
        }
    }

    /// 从 RGBA 图片构造，供测试使用。
    init(rgba: [UInt8], width: Int) {
        regions = TableArea.allCases.map { area in
            var region = TableRegion(area: area)
            for row in 0..<region.height {
                for column in 0..<region.width {
                    let source = ((area.y0 + row) * width + area.x0 + column) * 4
                    let r = Double(rgba[source])
                    let g = Double(rgba[source + 1])
                    let b = Double(rgba[source + 2])
                    let index = row * region.width + column
                    region.luma[index] = UInt8(max(0, min(255, 0.299 * r + 0.587 * g + 0.114 * b)))
                    region.cb[index] = UInt8(max(0, min(255, 128 - 0.168736 * r - 0.331264 * g + 0.5 * b)))
                    region.cr[index] = UInt8(max(0, min(255, 128 + 0.5 * r - 0.418688 * g - 0.081312 * b)))
                }
            }
            return region
        }
    }

    private static func expand(_ value: UInt8) -> UInt8 {
        UInt8(max(0, min(255, (Int(value) - 16) * 255 / 219)))
    }
}

/// 读取三块出牌区。同一读数连续出现两次才算数，避开发牌动画和特效。
final class TableReader {
    private enum Reading: Equatable {
        case empty
        case cards([Card])
    }

    private enum Block {
        case empty
        case unreadable
        case cards(left: Int, count: Int)
    }

    private static let cardWidth = 120
    private static let cardStep = 55
    private static let inkLuma: UInt8 = 150
    private static let minInkPixels = 12
    private static let maxGlyphDistance: Float = 0.16

    private var current: [TableArea: Reading] = [:]
    private var pending: [TableArea: (reading: Reading, repeats: Int)] = [:]

    /// 读到过牌，说明画面方向是对的。
    private(set) var hasReadCards = false

    /// 返回这一帧新确认的牌。
    func read(_ frame: TableFrame) -> [SeenCard] {
        var newCards: [SeenCard] = []
        for region in frame.regions {
            guard let reading = reading(of: region) else { continue }

            let repeats = pending[region.area]?.reading == reading ? pending[region.area]!.repeats + 1 : 1
            pending[region.area] = (reading, repeats)
            guard repeats == 2, current[region.area] != reading else { continue }

            current[region.area] = reading
            if case .cards(let cards) = reading {
                hasReadCards = true
                newCards += cards.map { SeenCard(card: $0, seat: region.area.seat) }
            }
        }
        return newCards
    }

    private func reading(of region: TableRegion) -> Reading? {
        switch block(in: region) {
        case .empty:
            return .empty
        case .unreadable:
            return nil
        case .cards(let left, let count):
            var cards: [Card] = []
            for index in 0..<count {
                guard let card = card(in: region, x: left + index * Self.cardStep) else { return nil }
                cards.append(card)
            }
            return .cards(cards)
        }
    }

    private func block(in region: TableRegion) -> Block {
        var first = -1
        var last = -1
        var cardColumns = 0
        for column in 0..<region.width {
            var white = 0
            for row in 0..<region.height {
                let index = row * region.width + column
                if region.luma[index] > 195,
                   abs(Int(region.cb[index]) - 128) < 24,
                   abs(Int(region.cr[index]) - 128) < 24 {
                    white += 1
                }
            }
            if white > 60 {
                if first < 0 { first = column }
                last = column
                cardColumns += 1
            }
        }
        guard cardColumns >= 40 else { return .empty }

        let count = Double(last - first + 1 - Self.cardWidth) / Double(Self.cardStep) + 1
        let rounded = count.rounded()
        guard abs(count - rounded) <= 0.08, rounded >= 1 else { return .unreadable }
        return .cards(left: first, count: Int(rounded))
    }

    private func card(in region: TableRegion, x: Int) -> Card? {
        let top = region.area.cardTop - region.area.y0

        guard let rankShape = glyph(in: region, x0: x + 4, y0: top + 8, x1: x + 50, y1: top + 58,
                                    width: GlyphTemplates.rankWidth, height: GlyphTemplates.rankHeight),
              let suitShape = glyph(in: region, x0: x + 4, y0: top + 60, x1: x + 40, y1: top + 94,
                                    width: GlyphTemplates.suitWidth, height: GlyphTemplates.suitHeight),
              let rankIndex = bestMatch(rankShape, in: GlyphTemplates.ranks, size: rankShape.count,
                                        options: Array(Rank.allCases.indices)) else { return nil }

        let red = isRed(in: region, x0: x + 4, y0: top + 60, x1: x + 40, y1: top + 94)
        let suitOptions = Suit.allCases.indices.filter { Suit.allCases[$0].isRed == red }
        guard let suitIndex = bestMatch(suitShape, in: GlyphTemplates.suits, size: suitShape.count,
                                        options: suitOptions) else { return nil }

        return Card(suit: Suit.allCases[suitIndex], rank: Rank.allCases[rankIndex])
    }

    /// 切出油墨部分并缩放到模板大小。
    private func glyph(in region: TableRegion, x0: Int, y0: Int, x1: Int, y1: Int, width: Int, height: Int) -> [Float]? {
        guard x0 >= 0, y0 >= 0, x1 <= region.width, y1 <= region.height else { return nil }

        var minX = x1, maxX = x0 - 1, minY = y1, maxY = y0 - 1, inkPixels = 0
        for row in y0..<y1 {
            for column in x0..<x1 where region.luma[row * region.width + column] < Self.inkLuma {
                minX = min(minX, column)
                maxX = max(maxX, column)
                minY = min(minY, row)
                maxY = max(maxY, row)
                inkPixels += 1
            }
        }
        guard inkPixels >= Self.minInkPixels else { return nil }

        let sourceWidth = maxX - minX + 1
        let sourceHeight = maxY - minY + 1

        func ink(_ column: Int, _ row: Int) -> Float {
            let x = minX + max(0, min(sourceWidth - 1, column))
            let y = minY + max(0, min(sourceHeight - 1, row))
            return region.luma[y * region.width + x] < Self.inkLuma ? 1 : 0
        }

        var shape = [Float](repeating: 0, count: width * height)
        for row in 0..<height {
            let sourceY = (Float(row) + 0.5) * Float(sourceHeight) / Float(height) - 0.5
            let y0 = Int(sourceY.rounded(.down))
            let yWeight = sourceY - Float(y0)
            for column in 0..<width {
                let sourceX = (Float(column) + 0.5) * Float(sourceWidth) / Float(width) - 0.5
                let x0 = Int(sourceX.rounded(.down))
                let xWeight = sourceX - Float(x0)
                let top = ink(x0, y0) * (1 - xWeight) + ink(x0 + 1, y0) * xWeight
                let bottom = ink(x0, y0 + 1) * (1 - xWeight) + ink(x0 + 1, y0 + 1) * xWeight
                shape[row * width + column] = top * (1 - yWeight) + bottom * yWeight
            }
        }
        return shape
    }

    private func isRed(in region: TableRegion, x0: Int, y0: Int, x1: Int, y1: Int) -> Bool {
        var total = 0
        var pixels = 0
        for row in y0..<y1 {
            for column in x0..<x1 {
                let index = row * region.width + column
                if region.luma[index] < Self.inkLuma {
                    total += Int(region.cr[index])
                    pixels += 1
                }
            }
        }
        return pixels > 0 && total / pixels > 150
    }

    /// 在候选模板里找最接近的一个，差距过大时返回 nil。
    private func bestMatch(_ shape: [Float], in templates: [UInt8], size: Int, options: [Int]) -> Int? {
        var best: Int?
        var bestDistance = Float.greatestFiniteMagnitude
        for option in options {
            var distance: Float = 0
            for index in 0..<size {
                distance += abs(Float(templates[option * size + index]) / 255 - shape[index])
            }
            distance /= Float(size)
            if distance < bestDistance {
                bestDistance = distance
                best = option
            }
        }
        return bestDistance <= Self.maxGlyphDistance ? best : nil
    }
}
