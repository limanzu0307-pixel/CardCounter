import AVFoundation
import AVKit
import SwiftUI
import UIKit

/// 把剩余牌表画成视频帧，借系统画中画悬浮在游戏上方。
@MainActor
final class PiPController: NSObject, ObservableObject {
    @Published private(set) var isActive = false

    let displayLayer = AVSampleBufferDisplayLayer()
    private var controller: AVPictureInPictureController?
    private var tracker = GameTracker()

    override init() {
        super.init()
        displayLayer.videoGravity = .resizeAspect
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
        let source = AVPictureInPictureController.ContentSource(
            sampleBufferDisplayLayer: displayLayer,
            playbackDelegate: self
        )
        let pip = AVPictureInPictureController(contentSource: source)
        pip.delegate = self
        pip.canStartPictureInPictureAutomaticallyFromInline = true
        controller = pip
    }

    func update(_ tracker: GameTracker) {
        self.tracker = tracker
        guard let sample = PiPFrameRenderer.sampleBuffer(for: tracker) else { return }
        if displayLayer.status == .failed { displayLayer.flush() }
        displayLayer.enqueue(sample)
    }

    func toggle() {
        guard let controller else { return }
        if controller.isPictureInPictureActive {
            controller.stopPictureInPicture()
        } else {
            // 画中画依赖音频会话，混音模式不会打断游戏声音
            try? AVAudioSession.sharedInstance().setCategory(.playback, options: .mixWithOthers)
            try? AVAudioSession.sharedInstance().setActive(true)
            update(tracker)
            controller.startPictureInPicture()
        }
    }
}

extension PiPController: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ controller: AVPictureInPictureController) {
        Task { @MainActor in self.isActive = true }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        Task { @MainActor in self.isActive = false }
    }
}

extension PiPController: AVPictureInPictureSampleBufferPlaybackDelegate {
    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController, setPlaying playing: Bool) {}

    nonisolated func pictureInPictureControllerTimeRangeForPlayback(_ controller: AVPictureInPictureController) -> CMTimeRange {
        CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
    }

    nonisolated func pictureInPictureControllerIsPlaybackPaused(_ controller: AVPictureInPictureController) -> Bool {
        false
    }

    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions) {}

    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController, skipByInterval skipInterval: CMTime, completion completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}

/// 画中画要求图层在视图层级里，这里用 1×1 的视图承载。
struct PiPHostView: UIViewRepresentable {
    let layer: AVSampleBufferDisplayLayer

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

enum PiPFrameRenderer {
    private static let width = 640
    private static let height = 420

    static func sampleBuffer(for tracker: GameTracker) -> CMSampleBuffer? {
        guard let pixelBuffer = pixelBuffer(for: tracker) else { return nil }

        var format: CMFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &format
        )
        guard let format else { return nil }

        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
            decodeTimeStamp: .invalid
        )
        var sample: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: format,
            sampleTiming: &timing,
            sampleBufferOut: &sample
        )
        guard let sample else { return nil }

        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true) as? [NSMutableDictionary] {
            attachments.first?[kCMSampleAttachmentKey_DisplayImmediately] = true
        }
        return sample
    }

    private static func pixelBuffer(for tracker: GameTracker) -> CVPixelBuffer? {
        let attributes = [kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()] as CFDictionary
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attributes, &buffer)
        guard let buffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        context.setFillColor(UIColor.black.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)

        UIGraphicsPushContext(context)
        draw(tracker)
        UIGraphicsPopContext()
        return buffer
    }

    private static func draw(_ tracker: GameTracker) {
        let font = UIFont.monospacedSystemFont(ofSize: 34, weight: .bold)
        let columnWidth: CGFloat = 50
        let rowHeight: CGFloat = 58

        func text(_ string: String, column: Int, row: Int, color: UIColor) {
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
            (string as NSString).draw(
                at: CGPoint(x: 16 + CGFloat(column) * columnWidth, y: 8 + CGFloat(row) * rowHeight),
                withAttributes: attributes
            )
        }

        for (column, rank) in Rank.allCases.enumerated() {
            text(rank == .ten ? "T" : rank.rawValue, column: column + 1, row: 0, color: .lightGray)
        }
        for (row, suit) in Suit.allCases.enumerated() {
            let color: UIColor = suit.isRed ? .systemRed : .white
            text(suit.rawValue, column: 0, row: row + 1, color: color)
            for (column, rank) in Rank.allCases.enumerated() {
                let count = tracker.remaining(Card(suit: suit, rank: rank))
                text("\(count)", column: column + 1, row: row + 1, color: count == 0 ? .darkGray : color)
            }
        }

        // 表格下方显示另外几家最近出的牌
        let lineFont = UIFont.monospacedSystemFont(ofSize: 25, weight: .semibold)
        let others = tracker.playerCount.seats.filter { $0 != .me }
        for (index, seat) in others.enumerated() {
            let cards = tracker.cards(of: seat).suffix(9).map(\.label).joined(separator: " ")
            let attributes: [NSAttributedString.Key: Any] = [.font: lineFont, .foregroundColor: UIColor.systemYellow]
            ("\(seat.rawValue) \(cards)" as NSString).draw(
                at: CGPoint(x: 16, y: 300 + CGFloat(index) * 38),
                withAttributes: attributes
            )
        }
    }
}
