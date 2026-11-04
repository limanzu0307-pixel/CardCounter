import CoreMedia
import ReplayKit

final class SampleHandler: RPBroadcastSampleHandler {
    private let recognizer: CardRecognizer = PendingGameRecognizer()
    private let store = BroadcastEventStore()
    private let frameInterval: TimeInterval = 0.33
    private var lastFrameTime = Date.distantPast

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        store.beat()
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video else { return }

        // 广播扩展内存限制很严，只抽帧处理
        let now = Date()
        guard now.timeIntervalSince(lastFrameTime) >= frameInterval else { return }
        lastFrameTime = now
        store.beat(at: now)

        guard let frame = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        store.append(recognizer.recognize(frame))
    }
}
