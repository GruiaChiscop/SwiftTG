// TelegramVideoNoteAssetWriterRecorder.swift

#if os(iOS) || os(macOS)
@preconcurrency import AVFoundation
import CoreImage
import Foundation
import QuartzCore

final class TelegramVideoNoteAssetWriterRecorder: NSObject, @unchecked Sendable {
    // MARK: Lifecycle

    override init() {
        super.init()
        videoOutput.alwaysDiscardsLateVideoFrames = false
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
        ]
        additionalVideoOutput.alwaysDiscardsLateVideoFrames = true
        additionalVideoOutput.videoSettings = videoOutput.videoSettings
        videoOutput.setSampleBufferDelegate(self, queue: videoCaptureQueue)
        additionalVideoOutput.setSampleBufferDelegate(self, queue: videoCaptureQueue)
        audioOutput.setSampleBufferDelegate(self, queue: audioCaptureQueue)
    }

    deinit {
        videoOutput.setSampleBufferDelegate(nil, queue: nil)
        additionalVideoOutput.setSampleBufferDelegate(nil, queue: nil)
        audioOutput.setSampleBufferDelegate(nil, queue: nil)
    }

    // MARK: Internal

    enum RecordingError: LocalizedError, Sendable {
        case alreadyRecording
        case audioSettingsUnavailable
        case noVideoFrames
        case writerFailed(String)
        case writerInitializationFailed(String)

        // MARK: Internal

        var errorDescription: String? {
            switch self {
            case .alreadyRecording:
                "A video message is already being recorded."
            case .audioSettingsUnavailable:
                "Audio recording settings are unavailable."
            case .noVideoFrames:
                "The camera did not produce any video frames."
            case .writerFailed(let message):
                "The video writer failed: \(message)"
            case .writerInitializationFailed(let message):
                "The video writer could not start: \(message)"
            }
        }
    }

    struct SegmentResult: Sendable {
        let duration: TimeInterval
        let url: URL
    }

    let videoOutput = AVCaptureVideoDataOutput()
    let additionalVideoOutput = AVCaptureVideoDataOutput()
    let audioOutput = AVCaptureAudioDataOutput()

    func selectCamera(position: AVCaptureDevice.Position) {
        selectedCameraLock.lock()
        selectedCameraPosition = position
        selectedCameraLock.unlock()
    }

    /// Non-blocking by design: never call this synchronously from `@MainActor`. `writerQueue` can be
    /// occupied for a while by `waitUntilReady`'s backpressure wait, and a blocking `.sync` there would
    /// freeze the caller's thread for as long as that wait takes.
    func start(
        to url: URL,
        completion: @escaping @MainActor @Sendable (UUID, Result<SegmentResult, RecordingError>) async -> Void,
    ) async throws -> UUID {
        try await withCheckedThrowingContinuation { continuation in
            writerQueue.async { [self] in
                do {
                    guard context == nil else { throw RecordingError.alreadyRecording }
                    guard let audioSettings = audioOutput.recommendedAudioSettingsForAssetWriter(writingTo: .mp4)
                    else {
                        throw RecordingError.audioSettingsUnavailable
                    }

                    try? FileManager.default.removeItem(at: url)
                    let writer: AVAssetWriter
                    do {
                        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
                        writer.shouldOptimizeForNetworkUse = false
                    } catch {
                        throw RecordingError.writerInitializationFailed(error.localizedDescription)
                    }

                    let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
                    audioInput.expectsMediaDataInRealTime = true
                    guard writer.canAdd(audioInput) else {
                        throw RecordingError.writerInitializationFailed("The encoded audio track could not be added.")
                    }
                    writer.add(audioInput)

                    let id = UUID()
                    let newContext = SegmentContext(
                        id: id,
                        url: url,
                        writer: writer,
                        audioInput: audioInput,
                        requestedStartTime: Self.hostTime(),
                        completion: completion,
                    )
                    context = newContext
                    activeContextLock.lock()
                    activeContextForCancellation = newContext
                    activeContextLock.unlock()
                    continuation.resume(returning: id)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stop() {
        let requestedStopTime = Self.hostTime()
        writerQueue.async { [weak self] in
            guard let self, let context, context.requestedStopTime == nil else { return }
            context.requestedStopTime = max(
                requestedStopTime,
                context.requestedStartTime + CMTime(seconds: 1, preferredTimescale: Self.timeScale),
            )
        }
    }

    /// Marks the active segment cancelled immediately, off `writerQueue`, so a concurrently running
    /// `waitUntilReady` backpressure wait notices within one poll instead of waiting for this method's
    /// own `writerQueue.async` block - which would otherwise be stuck behind that same wait.
    func cancel() {
        activeContextLock.lock()
        let contextToCancel = activeContextForCancellation
        activeContextLock.unlock()
        contextToCancel?.requestCancellation()

        writerQueue.async { [weak self] in
            guard let self, let context else { return }
            self.context = nil
            activeContextLock.lock()
            if activeContextForCancellation === context {
                activeContextForCancellation = nil
            }
            activeContextLock.unlock()
            context.isFinishing = true
            context.writer.cancelWriting()
            try? FileManager.default.removeItem(at: context.url)
        }
    }

    // MARK: Private

    private final class SegmentContext: @unchecked Sendable {
        // MARK: Lifecycle

        init(
            id: UUID,
            url: URL,
            writer: AVAssetWriter,
            audioInput: AVAssetWriterInput,
            requestedStartTime: CMTime,
            completion: @escaping @MainActor @Sendable (UUID, Result<SegmentResult, RecordingError>) async -> Void,
        ) {
            self.id = id
            self.url = url
            self.writer = writer
            self.audioInput = audioInput
            self.requestedStartTime = requestedStartTime
            self.completion = completion
        }

        // MARK: Internal

        let id: UUID
        let url: URL
        let writer: AVAssetWriter
        let audioInput: AVAssetWriterInput
        let requestedStartTime: CMTime
        let completion: @MainActor @Sendable (UUID, Result<SegmentResult, RecordingError>) async -> Void
        var videoInput: AVAssetWriterInput?
        var requestedStopTime: CMTime?
        var firstVideoTime: CMTime?
        var lastVideoTime: CMTime?
        var pendingAudioBuffers = [CMSampleBuffer]()
        var startedSession = false
        var hasAllVideoBuffers = false
        var hasAllAudioBuffers = false
        /// Only ever read/written from `writerQueue`; safe to leave as a plain `var`.
        var isFinishing = false

        /// Set from `cancel()`, which may run on any thread (including `@MainActor`) while
        /// `writerQueue` is busy. Guarded by `cancellationLock` since it's read from `writerQueue`
        /// (inside the backpressure spin-wait) concurrently with that write.
        var isCancelled: Bool {
            cancellationLock.lock()
            defer { cancellationLock.unlock() }
            return isCancelledStorage
        }

        func requestCancellation() {
            cancellationLock.lock()
            isCancelledStorage = true
            cancellationLock.unlock()
        }

        // MARK: Private

        private let cancellationLock = NSLock()
        private var isCancelledStorage = false
    }

    private final class SquareFrameProcessor {
        // MARK: Internal

        func process(_ sampleBuffer: CMSampleBuffer, side: Int) -> CMSampleBuffer? {
            guard let sourceBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
            if outputPool == nil {
                var pool: CVPixelBufferPool?
                let status = CVPixelBufferPoolCreate(
                    nil,
                    [kCVPixelBufferPoolMinimumBufferCountKey as String: 4] as CFDictionary,
                    [
                        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                        kCVPixelBufferWidthKey as String: side,
                        kCVPixelBufferHeightKey as String: side,
                        kCVPixelBufferIOSurfacePropertiesKey as String: [:],
                    ] as CFDictionary,
                    &pool,
                )
                guard status == kCVReturnSuccess, let pool else { return nil }
                outputPool = pool
            }
            guard let outputPool else { return nil }

            var optionalOutputBuffer: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(nil, outputPool, &optionalOutputBuffer) == kCVReturnSuccess,
                  let outputBuffer = optionalOutputBuffer
            else { return nil }

            let source = CIImage(cvPixelBuffer: sourceBuffer)
            let squareSide = min(source.extent.width, source.extent.height)
            let crop = CGRect(
                x: source.extent.midX - squareSide / 2,
                y: source.extent.midY - squareSide / 2,
                width: squareSide,
                height: squareSide,
            )
            let scale = CGFloat(side) / squareSide
            let outputImage = source
                .cropped(to: crop)
                .transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
                .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                .cropped(to: CGRect(x: 0, y: 0, width: side, height: side))
            imageContext.render(
                outputImage,
                to: outputBuffer,
                bounds: CGRect(x: 0, y: 0, width: side, height: side),
                colorSpace: colorSpace,
            )

            if outputFormatDescription == nil {
                var formatDescription: CMVideoFormatDescription?
                guard CMVideoFormatDescriptionCreateForImageBuffer(
                    allocator: nil,
                    imageBuffer: outputBuffer,
                    formatDescriptionOut: &formatDescription,
                ) == noErr else { return nil }
                outputFormatDescription = formatDescription
            }
            guard let outputFormatDescription else { return nil }

            var timing = CMSampleTimingInfo(
                duration: CMSampleBufferGetDuration(sampleBuffer),
                presentationTimeStamp: CMSampleBufferGetPresentationTimeStamp(sampleBuffer),
                decodeTimeStamp: CMSampleBufferGetDecodeTimeStamp(sampleBuffer),
            )
            var outputSampleBuffer: CMSampleBuffer?
            guard CMSampleBufferCreateForImageBuffer(
                allocator: kCFAllocatorDefault,
                imageBuffer: outputBuffer,
                dataReady: true,
                makeDataReadyCallback: nil,
                refcon: nil,
                formatDescription: outputFormatDescription,
                sampleTiming: &timing,
                sampleBufferOut: &outputSampleBuffer,
            ) == noErr else { return nil }
            return outputSampleBuffer
        }

        // MARK: Private

        private let colorSpace = CGColorSpaceCreateDeviceRGB()
        private let imageContext = CIContext(options: [.cacheIntermediates: false])
        private var outputFormatDescription: CMVideoFormatDescription?
        private var outputPool: CVPixelBufferPool?
    }

    private static let outputSide = 480
    private static let timeScale = CMTimeScale(NSEC_PER_SEC)
    /// Upper bound on how long `waitUntilReady` will spin for a stalled `AVAssetWriterInput` before
    /// giving up and failing the segment. Guards against a genuinely wedged encoder (not just a
    /// pending cancel/stop, which `SegmentContext.isCancelled` already resolves promptly).
    private static let maxBackpressureWait: TimeInterval = 5

    private let videoCaptureQueue = DispatchQueue(
        label: "com.gruiachiscop.BetterTG.video-note-capture",
        qos: .userInitiated,
    )
    private let audioCaptureQueue = DispatchQueue(
        label: "com.gruiachiscop.BetterTG.video-note-audio",
        qos: .userInitiated,
    )
    private let writerQueue = DispatchQueue(
        label: "com.gruiachiscop.BetterTG.video-note-writer",
        qos: .userInitiated,
    )
    private let frameProcessor = SquareFrameProcessor()
    private let selectedCameraLock = NSLock()
    private var context: SegmentContext?
    private var selectedCameraPosition = AVCaptureDevice.Position.front

    /// Mirrors `context` for `cancel()`'s benefit only, so it can signal cancellation without
    /// waiting for a turn on `writerQueue`. Always updated alongside `context` under `activeContextLock`.
    private let activeContextLock = NSLock()
    private var activeContextForCancellation: SegmentContext?

    private static func hostTime() -> CMTime {
        CMTime(seconds: CACurrentMediaTime(), preferredTimescale: timeScale)
    }

    private static func videoSettings() -> [String: Any] {
        [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: outputSide,
            AVVideoHeightKey: outputSide,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 1_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoH264EntropyModeKey: AVVideoH264EntropyModeCABAC,
            ],
        ]
    }

    private func appendVideo(_ sampleBuffer: CMSampleBuffer, to context: SegmentContext) {
        guard !context.isFinishing else { return }
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard presentationTime >= context.requestedStartTime else { return }

        if context.videoInput == nil {
            let input = AVAssetWriterInput(
                mediaType: .video,
                outputSettings: Self.videoSettings(),
                sourceFormatHint: CMSampleBufferGetFormatDescription(sampleBuffer),
            )
            input.expectsMediaDataInRealTime = true
            guard context.writer.canApply(outputSettings: Self.videoSettings(), forMediaType: .video),
                  context.writer.canAdd(input)
            else {
                fail(context, message: "The encoded video track could not be added")
                return
            }
            context.writer.add(input)
            context.videoInput = input
        }

        if context.writer.status == .unknown {
            guard context.writer.startWriting() else {
                fail(context, message: context.writer.error?.localizedDescription ?? "Unknown writer error")
                return
            }
            return
        }
        if context.writer.status == .writing, !context.startedSession {
            context.writer.startSession(atSourceTime: presentationTime)
            context.firstVideoTime = presentationTime
            context.lastVideoTime = presentationTime
            context.startedSession = true
        }
        guard context.writer.status == .writing, context.startedSession, let videoInput = context.videoInput else {
            fail(context, message: context.writer.error?.localizedDescription ?? "The writer stopped unexpectedly")
            return
        }

        if let requestedStopTime = context.requestedStopTime, presentationTime > requestedStopTime {
            context.hasAllVideoBuffers = true
            maybeFinish(context)
            return
        }
        guard waitUntilReady(videoInput, context: context) else { return }
        if videoInput.append(sampleBuffer) {
            context.lastVideoTime = presentationTime
            guard appendPendingAudio(to: context) else {
                fail(context, message: "Buffered audio could not be written")
                return
            }
        } else {
            fail(context, message: context.writer.error?.localizedDescription ?? "A video frame could not be written")
        }
    }

    private func appendAudio(_ sampleBuffer: CMSampleBuffer, to context: SegmentContext) {
        guard !context.isFinishing else { return }
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard presentationTime >= context.requestedStartTime else { return }

        if let requestedStopTime = context.requestedStopTime, presentationTime > requestedStopTime {
            context.hasAllAudioBuffers = true
            maybeFinish(context)
            return
        }
        guard context.startedSession, let lastVideoTime = context.lastVideoTime else {
            if context.pendingAudioBuffers.count < 300 {
                context.pendingAudioBuffers.append(sampleBuffer)
            }
            return
        }
        if sampleBuffer.endTime > lastVideoTime {
            if context.pendingAudioBuffers.count < 300 {
                context.pendingAudioBuffers.append(sampleBuffer)
            }
        } else if !appendAudioImmediately(sampleBuffer, to: context) {
            fail(context, message: context.writer.error?.localizedDescription ?? "An audio sample could not be written")
        }
    }

    private func appendPendingAudio(to context: SegmentContext) -> Bool {
        guard let lastVideoTime = context.lastVideoTime else { return true }
        var remaining = [CMSampleBuffer]()
        remaining.reserveCapacity(context.pendingAudioBuffers.count)
        for sampleBuffer in context.pendingAudioBuffers {
            if sampleBuffer.endTime <= lastVideoTime {
                guard appendAudioImmediately(sampleBuffer, to: context) else { return false }
            } else {
                remaining.append(sampleBuffer)
            }
        }
        context.pendingAudioBuffers = remaining
        return true
    }

    private func appendAudioImmediately(_ sampleBuffer: CMSampleBuffer, to context: SegmentContext) -> Bool {
        guard waitUntilReady(context.audioInput, context: context) else { return false }
        return context.audioInput.append(sampleBuffer)
    }

    private func waitUntilReady(_ input: AVAssetWriterInput, context: SegmentContext) -> Bool {
        let deadline = DispatchTime.now() + Self.maxBackpressureWait
        while !input.isReadyForMoreMediaData {
            guard !context.isFinishing, !context.isCancelled, context.writer.status == .writing,
                  DispatchTime.now() < deadline
            else { return false }
            Thread.sleep(forTimeInterval: 0.005)
        }
        return true
    }

    private func maybeFinish(_ context: SegmentContext) {
        guard context.hasAllVideoBuffers, context.hasAllAudioBuffers, !context.isFinishing else { return }
        context.isFinishing = true
        guard context.writer.status == .writing,
              let firstVideoTime = context.firstVideoTime,
              let lastVideoTime = context.lastVideoTime,
              let videoInput = context.videoInput
        else {
            context.writer.cancelWriting()
            complete(context, with: .failure(.noVideoFrames))
            return
        }

        videoInput.markAsFinished()
        context.audioInput.markAsFinished()
        context.pendingAudioBuffers.removeAll()
        let duration = max(0, (lastVideoTime - firstVideoTime).seconds)
        context.writer.finishWriting { [weak self, context] in
            self?.writerQueue.async { [weak self, context] in
                guard let self else { return }
                if context.writer.status == .completed {
                    complete(context, with: .success(.init(duration: duration, url: context.url)))
                } else {
                    complete(
                        context,
                        with: .failure(.writerFailed(
                            context.writer.error?.localizedDescription ?? "The MP4 file could not be finalized",
                        )),
                    )
                }
            }
        }
    }

    private func fail(_ context: SegmentContext, message: String) {
        guard !context.isFinishing else { return }
        context.isFinishing = true
        context.writer.cancelWriting()
        complete(context, with: .failure(.writerFailed(message)))
    }

    private func complete(_ context: SegmentContext, with result: Result<SegmentResult, RecordingError>) {
        guard self.context === context else { return }
        self.context = nil
        activeContextLock.lock()
        if activeContextForCancellation === context {
            activeContextForCancellation = nil
        }
        activeContextLock.unlock()
        let id = context.id
        let completion = context.completion
        Task { @MainActor in
            await completion(id, result)
        }
    }

    private func selectedCamera() -> AVCaptureDevice.Position {
        selectedCameraLock.lock()
        defer { selectedCameraLock.unlock() }
        return selectedCameraPosition
    }
}

private extension CMSampleBuffer {
    var endTime: CMTime {
        CMSampleBufferGetPresentationTimeStamp(self) + CMSampleBufferGetDuration(self)
    }
}

extension TelegramVideoNoteAssetWriterRecorder: AVCaptureVideoDataOutputSampleBufferDelegate,
    AVCaptureAudioDataOutputSampleBufferDelegate
{
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection,
    ) {
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }
        if output === videoOutput || output === additionalVideoOutput {
            #if os(iOS)
            let position = connection.inputPorts.first?.sourceDevicePosition ?? selectedCamera()
            #else
            let position = selectedCamera()
            #endif
            guard position == selectedCamera(),
                  let processedBuffer = frameProcessor.process(sampleBuffer, side: Self.outputSide)
            else { return }
            nonisolated(unsafe) let bufferForWriter = processedBuffer
            writerQueue.async { [weak self] in
                guard let self, let context else { return }
                appendVideo(bufferForWriter, to: context)
            }
        } else if output === audioOutput {
            nonisolated(unsafe) let bufferForWriter = sampleBuffer
            writerQueue.async { [weak self] in
                guard let self, let context else { return }
                appendAudio(bufferForWriter, to: context)
            }
        }
    }
}
#endif
