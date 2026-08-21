// TelegramCallSampleBufferVideoView.swift

import AVFoundation
import CoreMedia
@preconcurrency import TgVoipWebrtc
import UIKit

// MARK: - TelegramCallSampleBufferVideoView

/// A second, independently-subscribed tgcalls renderer used by Picture in Picture. This mirrors
/// Telegram-iOS's sample-buffer path and leaves the native Metal view mounted in the call UI.
@MainActor final class TelegramCallSampleBufferVideoView: UIView,
    @preconcurrency OngoingCallThreadLocalContextWebrtcVideoView
{
    // MARK: Lifecycle

    init(engine: TelegramCallEngine, isIncoming: Bool) {
        self.engine = engine
        super.init(frame: .zero)

        isUserInteractionEnabled = false
        sampleBufferLayer.videoGravity = .resizeAspectFill
        sampleBufferLayer.preventsDisplaySleepDuringVideoPlayback = true

        self.outputIdentifier = engine.addVideoOutput(isIncoming: isIncoming) { [weak self] frame in
            DispatchQueue.main.async { [weak self] in
                self?.addFrame(frame)
            }
        }
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let outputIdentifier {
            engine.removeVideoOutput(outputIdentifier)
        }
    }

    // MARK: Internal

    override static var layerClass: AnyClass { AVSampleBufferDisplayLayer.self }

    private(set) var orientation = OngoingCallVideoOrientationWebrtc.orientation0
    private(set) var aspect: CGFloat = 3 / 4

    var sampleBufferLayer: AVSampleBufferDisplayLayer {
        layer as! AVSampleBufferDisplayLayer
    }

    func setOnFirstFrameReceived(_ onFirstFrameReceived: ((Float) -> Void)?) {
        self.onFirstFrameReceived = onFirstFrameReceived
        didReceiveFirstFrame = false
    }

    func setOnOrientationUpdated(
        _ onOrientationUpdated: ((OngoingCallVideoOrientationWebrtc, CGFloat) -> Void)?,
    ) {
        self.onOrientationUpdated = onOrientationUpdated
    }

    func setOnIsMirroredUpdated(_ onIsMirroredUpdated: ((Bool) -> Void)?) {
        self.onIsMirroredUpdated = onIsMirroredUpdated
    }

    func updateIsEnabled(_ isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    // MARK: Private

    private let engine: TelegramCallEngine
    private var outputIdentifier: UUID?
    private var isEnabled = true
    private var didReceiveFirstFrame = false
    private var isMirrored = false
    private var onFirstFrameReceived: ((Float) -> Void)?
    private var onOrientationUpdated: ((OngoingCallVideoOrientationWebrtc, CGFloat) -> Void)?
    private var onIsMirroredUpdated: ((Bool) -> Void)?

    private static func pixelBuffer(from frame: CallVideoFrameData) -> CVPixelBuffer? {
        if let nativeBuffer = frame.buffer as? CallVideoFrameNativePixelBuffer {
            return nativeBuffer.pixelBuffer
        }

        let width = Int(frame.width)
        let height = Int(frame.height)
        guard let pixelBuffer = makeNV12PixelBuffer(width: width, height: height) else { return nil }

        if let nv12Buffer = frame.buffer as? CallVideoFrameNV12Buffer {
            return copyNV12Buffer(nv12Buffer, into: pixelBuffer) ? pixelBuffer : nil
        }
        if let i420Buffer = frame.buffer as? CallVideoFrameI420Buffer {
            return copyI420Buffer(i420Buffer, into: pixelBuffer) ? pixelBuffer : nil
        }
        return nil
    }

    private static func makeNV12PixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        let attributes = [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
            attributes,
            &pixelBuffer,
        )
        return status == kCVReturnSuccess ? pixelBuffer : nil
    }

    private static func copyNV12Buffer(
        _ source: CallVideoFrameNV12Buffer,
        into destination: CVPixelBuffer,
    ) -> Bool {
        guard CVPixelBufferLockBaseAddress(destination, []) == kCVReturnSuccess else { return false }
        defer { CVPixelBufferUnlockBaseAddress(destination, []) }

        guard let destinationY = CVPixelBufferGetBaseAddressOfPlane(destination, 0),
              let destinationUV = CVPixelBufferGetBaseAddressOfPlane(destination, 1)
        else { return false }

        let width = Int(source.width)
        let height = Int(source.height)
        copyPlane(
            source.y,
            sourceStride: Int(source.strideY),
            destination: destinationY,
            destinationStride: CVPixelBufferGetBytesPerRowOfPlane(destination, 0),
            rowBytes: width,
            rowCount: height,
        )
        copyPlane(
            source.uv,
            sourceStride: Int(source.strideUV),
            destination: destinationUV,
            destinationStride: CVPixelBufferGetBytesPerRowOfPlane(destination, 1),
            rowBytes: width,
            rowCount: (height + 1) / 2,
        )
        return true
    }

    private static func copyI420Buffer(
        _ source: CallVideoFrameI420Buffer,
        into destination: CVPixelBuffer,
    ) -> Bool {
        guard CVPixelBufferLockBaseAddress(destination, []) == kCVReturnSuccess else { return false }
        defer { CVPixelBufferUnlockBaseAddress(destination, []) }

        guard let destinationY = CVPixelBufferGetBaseAddressOfPlane(destination, 0),
              let destinationUV = CVPixelBufferGetBaseAddressOfPlane(destination, 1)
        else { return false }

        let width = Int(source.width)
        let height = Int(source.height)
        copyPlane(
            source.y,
            sourceStride: Int(source.strideY),
            destination: destinationY,
            destinationStride: CVPixelBufferGetBytesPerRowOfPlane(destination, 0),
            rowBytes: width,
            rowCount: height,
        )

        let chromaWidth = (width + 1) / 2
        let chromaHeight = (height + 1) / 2
        let destinationStride = CVPixelBufferGetBytesPerRowOfPlane(destination, 1)
        source.u.withUnsafeBytes { uBytes in
            source.v.withUnsafeBytes { vBytes in
                guard let sourceU = uBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                      let sourceV = vBytes.baseAddress?.assumingMemoryBound(to: UInt8.self)
                else { return }
                let destinationUV = destinationUV.assumingMemoryBound(to: UInt8.self)
                for row in 0..<chromaHeight {
                    let uRow = sourceU.advanced(by: row * Int(source.strideU))
                    let vRow = sourceV.advanced(by: row * Int(source.strideV))
                    let destinationRow = destinationUV.advanced(by: row * destinationStride)
                    for column in 0..<chromaWidth {
                        destinationRow[column * 2] = uRow[column]
                        destinationRow[column * 2 + 1] = vRow[column]
                    }
                }
            }
        }
        return true
    }

    private static func copyPlane(
        _ source: Data,
        sourceStride: Int,
        destination: UnsafeMutableRawPointer,
        destinationStride: Int,
        rowBytes: Int,
        rowCount: Int,
    ) {
        source.withUnsafeBytes { sourceBytes in
            guard let sourceAddress = sourceBytes.baseAddress else { return }
            for row in 0..<rowCount {
                destination
                    .advanced(by: row * destinationStride)
                    .copyMemory(from: sourceAddress.advanced(by: row * sourceStride), byteCount: rowBytes)
            }
        }
    }

    private static func sampleBuffer(from pixelBuffer: CVPixelBuffer) -> CMSampleBuffer? {
        var formatDescription: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDescription,
        ) == noErr, let formatDescription
        else { return nil }

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 30),
            presentationTimeStamp: .zero,
            decodeTimeStamp: .invalid,
        )
        var sampleBuffer: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: formatDescription,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer,
        ) == noErr, let sampleBuffer
        else { return nil }

        if let attachments = CMSampleBufferGetSampleAttachmentsArray(
            sampleBuffer,
            createIfNecessary: true,
        ) as? [NSMutableDictionary], let firstAttachment = attachments.first {
            firstAttachment[kCMSampleAttachmentKey_DisplayImmediately] = true
        }
        return sampleBuffer
    }

    private func addFrame(_ frame: CallVideoFrameData) {
        let width = Int(frame.width)
        let height = Int(frame.height)
        guard width > 0, height > 0 else { return }

        let updatedAspect = CGFloat(width) / CGFloat(height)
        if aspect != updatedAspect || orientation != frame.orientation {
            aspect = updatedAspect
            orientation = frame.orientation
            onOrientationUpdated?(orientation, aspect)
        }

        let updatedIsMirrored = frame.mirrorHorizontally != frame.mirrorVertically
        if isMirrored != updatedIsMirrored {
            isMirrored = updatedIsMirrored
            onIsMirroredUpdated?(updatedIsMirrored)
        }

        if !didReceiveFirstFrame {
            didReceiveFirstFrame = true
            onFirstFrameReceived?(Float(aspect))
        }

        guard isEnabled, let pixelBuffer = Self.pixelBuffer(from: frame) else { return }
        guard let sampleBuffer = Self.sampleBuffer(from: pixelBuffer) else { return }
        let renderer = sampleBufferLayer.sampleBufferRenderer
        if renderer.status == .failed {
            renderer.flush()
        }
        renderer.enqueue(sampleBuffer)
    }
}
