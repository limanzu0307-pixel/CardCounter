import CoreMedia
import ImageIO
import ReplayKit

final class SampleHandler: RPBroadcastSampleHandler {
    private let reader = TableReader()
    private let store = BroadcastEventStore()
    private let frameInterval: TimeInterval = 0.33
    private var lastFrameTime = Date.distantPast
    private var lockedOrientation: CGImagePropertyOrientation?
    private var frameCount = 0

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        store.beat()
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video else { return }

        // 广播扩展内存限制很严，只抽帧处理
        let now = Date()
        guard now.timeIntervalSince(lastFrameTime) >= frameInterval else { return }
        lastFrameTime = now
        frameCount += 1
        store.beat(at: now)

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let resolved = resolveOrientation(of: sampleBuffer, pixelBuffer: pixelBuffer)
        guard let frame = TableFrame(pixelBuffer: pixelBuffer, orientation: resolved) else { return }

        store.append(reader.read(frame))
        if reader.hasReadCards, lockedOrientation == nil {
            lockedOrientation = resolved
        }
    }

    private func resolveOrientation(of sampleBuffer: CMSampleBuffer, pixelBuffer: CVPixelBuffer) -> CGImagePropertyOrientation {
        if let lockedOrientation { return lockedOrientation }

        let attachment = CMGetAttachment(sampleBuffer, key: RPVideoSampleOrientationKey as CFString, attachmentModeOut: nil)
        let reported = (attachment as? NSNumber)
            .flatMap { CGImagePropertyOrientation(rawValue: $0.uint32Value) } ?? .up

        // 横屏游戏的画面可能竖着存放且没有方向标记，这时两个方向轮流试
        let portrait = CVPixelBufferGetWidth(pixelBuffer) < CVPixelBufferGetHeight(pixelBuffer)
        if portrait, reported == .up || reported == .down {
            return frameCount / 9 % 2 == 0 ? .left : .right
        }
        return reported
    }
}
