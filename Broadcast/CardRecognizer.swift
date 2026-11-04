import CoreVideo

/// 从一帧屏幕画面里找出“新打出的牌”。
protocol CardRecognizer {
    func recognize(_ frame: CVPixelBuffer) -> [Card]
}

/// 占位实现：拿到目标游戏的录屏后，再换成针对该游戏的识别器。
struct PendingGameRecognizer: CardRecognizer {
    func recognize(_ frame: CVPixelBuffer) -> [Card] { [] }
}
