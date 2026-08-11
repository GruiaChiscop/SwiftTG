// TelegramVideoNoteRecorder.swift

@preconcurrency import AVFoundation
import CoreImage
import Observation
import SwiftUI
@preconcurrency import TDLibKit

// MARK: - TelegramVideoNoteRecordingArtifact

struct TelegramVideoNoteRecordingArtifact: Sendable {
    let url: URL
    let duration: Int
    let length: Int
    let isViewOnce: Bool
}

// MARK: - TelegramVideoNoteRecorder

@MainActor @Observable final class TelegramVideoNoteRecorder: NSObject,
    AVCaptureFileOutputRecordingDelegate
{
    // MARK: Internal

    private(set) var isPreparing = false
    private(set) var isRecording = false
    private(set) var isPaused = false
    private(set) var isFinalizing = false
    private(set) var duration: TimeInterval = 0
    private(set) var errorMessage: String?
    var isViewOnce = false

    let captureSession = AVCaptureSession()

    func start(
        onFinished: @escaping @MainActor (TelegramVideoNoteRecordingArtifact, MessageSchedulingState?) -> Void,
    ) async {
        guard !isPreparing, !isRecording, !isPaused, !isFinalizing else { return }
        isPreparing = true
        errorMessage = nil
        completion = onFinished

        guard await AVCaptureDevice.requestAccess(for: .video) else {
            fail("Camera access is required to record a video message.")
            return
        }
        guard isPreparing else { return }
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            fail("Microphone access is required to record a video message.")
            return
        }
        guard isPreparing else { return }

        do {
            #if os(iOS)
            try configureAudioSessionForRecording()
            #endif
            try configureSessionIfNeeded()
            let sessionStartTask = enqueueCaptureSessionOperation(shouldRun: true)
            await sessionStartTask.value
            guard isPreparing else { return }
            guard captureSession.isRunning else {
                throw TelegramVideoNoteRecorderError.captureSessionUnavailable
            }

            rawRecordingURLs.removeAll()
            accumulatedDuration = 0
            duration = 0
            isPreparing = false
            try startSegment()
        } catch {
            fail("Video recording could not start: \(error.localizedDescription)")
        }
    }

    func pause() {
        guard isRecording, !shouldPauseAfterCurrentSegment else { return }
        updateDuration()
        shouldPauseAfterCurrentSegment = true
        stopTimer()
        #if os(iOS)
        assetWriterRecorder.stop()
        #else
        output.stopRecording()
        #endif
    }

    func resume() {
        guard isPaused, !isFinalizing,
              TelegramVideoNoteRecordingLimits.remainingDuration(after: accumulatedDuration) > 0
        else { return }
        do {
            try startSegment()
        } catch {
            fail("Video recording could not resume: \(error.localizedDescription)")
            cleanupSession()
        }
    }

    func stop(schedulingState: MessageSchedulingState? = nil) {
        guard isRecording || isPaused else { return }
        pendingSchedulingState = schedulingState
        shouldPauseAfterCurrentSegment = false
        shouldDiscard = false
        updateDuration()
        isRecording = false
        isPaused = false
        isFinalizing = true
        stopTimer()
        #if os(iOS)
        if currentSegmentID != nil {
            assetWriterRecorder.stop()
        } else {
            Task { await finalizeRecording() }
        }
        #else
        if currentRawRecordingURL != nil {
            if output.isRecording {
                output.stopRecording()
            }
        } else {
            Task { await finalizeRecording() }
        }
        #endif
    }

    func cancel() {
        guard isPreparing || isRecording || isPaused || isFinalizing || currentRawRecordingURL != nil
            || !rawRecordingURLs.isEmpty
        else { return }
        shouldDiscard = true
        shouldPauseAfterCurrentSegment = false
        completion = nil
        pendingSchedulingState = nil
        if isFinalizing {
            return
        }
        isPreparing = false
        isRecording = false
        isPaused = false
        isFinalizing = false
        stopTimer()
        #if os(iOS)
        assetWriterRecorder.cancel()
        currentSegmentID = nil
        cleanupSession()
        #else
        if output.isRecording {
            output.stopRecording()
        } else if currentRawRecordingURL == nil {
            cleanupSession()
        }
        #endif
    }

    func clearError() {
        errorMessage = nil
    }

    nonisolated func fileOutput(
        _: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from _: [AVCaptureConnection],
        error: (any Swift.Error)?,
    ) {
        #if os(macOS)
        Task { @MainActor [weak self] in
            await self?.finishRecording(at: outputFileURL, error: error)
        }
        #endif
    }

    nonisolated func fileOutput(
        _: AVCaptureFileOutput,
        didStartRecordingTo outputFileURL: URL,
        from _: [AVCaptureConnection],
    ) {
        #if os(macOS)
        Task { @MainActor [weak self] in
            self?.recordingDidStart(at: outputFileURL)
        }
        #endif
    }

    // MARK: Private

    #if os(iOS)
    @ObservationIgnored private let assetWriterRecorder = TelegramVideoNoteAssetWriterRecorder()
    @ObservationIgnored private var currentSegmentID: UUID?
    #else
    @ObservationIgnored private let output = AVCaptureMovieFileOutput()
    #endif
    @ObservationIgnored private var completion:
        (@MainActor (TelegramVideoNoteRecordingArtifact, MessageSchedulingState?) -> Void)?
    @ObservationIgnored private var configured = false
    @ObservationIgnored private var pendingSchedulingState: MessageSchedulingState?
    @ObservationIgnored private var rawRecordingURLs = [URL]()
    @ObservationIgnored private var currentRawRecordingURL: URL?
    @ObservationIgnored private var accumulatedDuration: TimeInterval = 0
    @ObservationIgnored private var recordingStartedAt: Foundation.Date?
    @ObservationIgnored private var shouldDiscard = false
    @ObservationIgnored private var shouldPauseAfterCurrentSegment = false
    @ObservationIgnored private var captureSessionOperationTask: Task<Void, Never>?
    @ObservationIgnored private var timerTask: Task<Void, Never>?

    #if os(iOS)
    private func configureAudioSessionForRecording() throws {
        let audioSession = AVAudioSession.sharedInstance()
        var options: AVAudioSession.CategoryOptions = [
            .allowBluetoothHFP,
            .defaultToSpeaker,
            .overrideMutedMicrophoneInterruption,
        ]
        if UIAccessibility.isVoiceOverRunning {
            options.insert(.mixWithOthers)
        }
        try audioSession.setCategory(
            .playAndRecord,
            mode: .videoRecording,
            policy: .default,
            options: options,
        )
        try audioSession.setActive(true)
    }
    #endif

    private func configureSessionIfNeeded() throws {
        guard !configured else { return }
        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }
        if captureSession.canSetSessionPreset(.high) {
            captureSession.sessionPreset = .high
        }

        #if os(iOS)
        let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            ?? AVCaptureDevice.default(for: .video)
        #else
        let videoDevice = AVCaptureDevice.default(for: .video)
        #endif
        guard let videoDevice else { throw TelegramVideoNoteRecorderError.cameraUnavailable }
        let videoInput = try AVCaptureDeviceInput(device: videoDevice)
        guard captureSession.canAddInput(videoInput) else {
            throw TelegramVideoNoteRecorderError.cameraUnavailable
        }
        captureSession.addInput(videoInput)

        guard let audioDevice = AVCaptureDevice.default(for: .audio) else {
            throw TelegramVideoNoteRecorderError.microphoneUnavailable
        }
        let audioInput = try AVCaptureDeviceInput(device: audioDevice)
        guard captureSession.canAddInput(audioInput) else {
            throw TelegramVideoNoteRecorderError.microphoneUnavailable
        }
        captureSession.addInput(audioInput)
        #if os(iOS)
        guard captureSession.canAddOutput(assetWriterRecorder.videoOutput),
              captureSession.canAddOutput(assetWriterRecorder.audioOutput)
        else { throw TelegramVideoNoteRecorderError.captureSessionUnavailable }
        captureSession.addOutput(assetWriterRecorder.videoOutput)
        captureSession.addOutput(assetWriterRecorder.audioOutput)
        captureSession.automaticallyConfiguresApplicationAudioSession = false
        if let connection = assetWriterRecorder.videoOutput.connection(with: .video),
           connection.isVideoRotationAngleSupported(90)
        {
            connection.videoRotationAngle = 90
        }
        #else
        guard captureSession.canAddOutput(output) else {
            throw TelegramVideoNoteRecorderError.captureSessionUnavailable
        }
        captureSession.addOutput(output)
        #endif
        configured = true
    }

    private func startSegment() throws {
        let remainingDuration = TelegramVideoNoteRecordingLimits.remainingDuration(after: accumulatedDuration)
        guard remainingDuration > 0 else {
            isPaused = false
            isFinalizing = true
            Task { await finalizeRecording() }
            return
        }

        #if os(iOS)
        let url = TelegramOutgoingFileStaging.shared.videoNoteAssetWriterFileURL()
        #else
        let url = TelegramOutgoingFileStaging.shared.videoNoteFileURL(isRawRecording: true)
        #endif
        currentRawRecordingURL = url
        recordingStartedAt = .now
        shouldPauseAfterCurrentSegment = false
        isPaused = false
        isRecording = true
        #if os(iOS)
        do {
            currentSegmentID = try assetWriterRecorder.start(to: url) { [weak self] id, result in
                await self?.finishAssetWriterSegment(id: id, result: result)
            }
        } catch {
            currentRawRecordingURL = nil
            recordingStartedAt = nil
            isRecording = false
            throw error
        }
        #else
        recordingStartedAt = nil
        output.maxRecordedDuration = CMTime(seconds: remainingDuration, preferredTimescale: 600)
        output.startRecording(to: url, recordingDelegate: self)
        #endif
        startTimer()
    }

    private func recordingDidStart(at url: URL) {
        #if os(macOS)
        guard currentRawRecordingURL == url else { return }
        recordingStartedAt = .now
        if shouldDiscard || shouldPauseAfterCurrentSegment || isFinalizing {
            output.stopRecording()
        }
        #endif
    }

    private func startTimer() {
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self, isRecording else { return }
                updateDuration()
                if duration >= TelegramVideoNoteRecordingLimits.maximumDuration {
                    stop()
                    return
                }
            }
        }
    }

    private func stopTimer() {
        timerTask?.cancel()
        timerTask = nil
    }

    private func updateDuration() {
        let currentDuration = recordingStartedAt.map { Date.now.timeIntervalSince($0) } ?? 0
        duration = TelegramVideoNoteRecordingLimits.totalDuration(
            completed: accumulatedDuration,
            current: currentDuration,
        )
    }

    private func finishRecording(at rawURL: URL, error: (any Swift.Error)?) async {
        stopTimer()
        isPreparing = false
        if shouldDiscard {
            TelegramOutgoingFileStaging.shared.discard(fileURL: rawURL)
            cleanupSession()
            return
        }
        if let error, !FileManager.default.fileExists(atPath: rawURL.path) {
            currentRawRecordingURL = nil
            recordingStartedAt = nil
            if shouldPauseAfterCurrentSegment {
                shouldPauseAfterCurrentSegment = false
                isRecording = false
                isPaused = true
                isFinalizing = false
                return
            }
            if isFinalizing {
                if rawRecordingURLs.isEmpty {
                    cleanupSession()
                } else {
                    await finalizeRecording()
                }
                return
            }
            fail("Video recording failed: \(error.localizedDescription)")
            cleanupSession()
            return
        }

        let currentDuration = recordingStartedAt.map { Date.now.timeIntervalSince($0) } ?? 0
        accumulatedDuration = TelegramVideoNoteRecordingLimits.totalDuration(
            completed: accumulatedDuration,
            current: currentDuration,
        )
        duration = accumulatedDuration
        recordingStartedAt = nil
        currentRawRecordingURL = nil
        rawRecordingURLs.append(rawURL)

        if shouldPauseAfterCurrentSegment,
           TelegramVideoNoteRecordingLimits.remainingDuration(after: accumulatedDuration) > 0
        {
            shouldPauseAfterCurrentSegment = false
            isRecording = false
            isPaused = true
            isFinalizing = false
            return
        }

        isRecording = false
        isPaused = false
        isFinalizing = true
        await finalizeRecording()
    }

    #if os(iOS)
    private func finishAssetWriterSegment(
        id: UUID,
        result: Result<
            TelegramVideoNoteAssetWriterRecorder.SegmentResult,
            TelegramVideoNoteAssetWriterRecorder.RecordingError,
        >,
    ) async {
        guard currentSegmentID == id else { return }
        currentSegmentID = nil
        stopTimer()
        isPreparing = false

        if shouldDiscard {
            if let currentRawRecordingURL {
                TelegramOutgoingFileStaging.shared.discard(fileURL: currentRawRecordingURL)
            }
            cleanupSession()
            return
        }

        switch result {
        case .failure(let error):
            currentRawRecordingURL = nil
            recordingStartedAt = nil
            if shouldPauseAfterCurrentSegment {
                shouldPauseAfterCurrentSegment = false
                isRecording = false
                isPaused = true
                isFinalizing = false
                return
            }
            fail("Video recording failed: \(error.localizedDescription)")
            cleanupSession()
        case .success(let segment):
            accumulatedDuration = TelegramVideoNoteRecordingLimits.totalDuration(
                completed: accumulatedDuration,
                current: segment.duration,
            )
            duration = accumulatedDuration
            recordingStartedAt = nil
            currentRawRecordingURL = nil
            rawRecordingURLs.append(segment.url)

            if shouldPauseAfterCurrentSegment,
               TelegramVideoNoteRecordingLimits.remainingDuration(after: accumulatedDuration) > 0
            {
                shouldPauseAfterCurrentSegment = false
                isRecording = false
                isPaused = true
                isFinalizing = false
                return
            }

            isRecording = false
            isPaused = false
            isFinalizing = true
            await finalizeRecording()
        }
    }
    #endif

    private func finalizeRecording() async {
        guard !rawRecordingURLs.isEmpty else {
            fail("Video message could not be prepared because no recording was captured.")
            cleanupSession()
            return
        }

        let outputURL = TelegramOutgoingFileStaging.shared.videoNoteFileURL()
        do {
            let duration = try await TelegramVideoNoteTranscoder.exportSquareVideo(
                sourceURLs: rawRecordingURLs,
                outputURL: outputURL,
                side: 480,
            )
            discardRawRecordings()
            if shouldDiscard {
                TelegramOutgoingFileStaging.shared.discard(fileURL: outputURL)
                cleanupSession()
                return
            }
            let artifact = TelegramVideoNoteRecordingArtifact(
                url: outputURL,
                duration: duration,
                length: 480,
                isViewOnce: isViewOnce,
            )
            let schedulingState = pendingSchedulingState
            let completion = completion
            cleanupSession()
            completion?(artifact, schedulingState)
        } catch {
            discardRawRecordings()
            TelegramOutgoingFileStaging.shared.discard(fileURL: outputURL)
            if shouldDiscard {
                cleanupSession()
                return
            }
            fail("Video message could not be prepared: \(error.localizedDescription)")
            cleanupSession()
        }
    }

    private func fail(_ message: String) {
        isPreparing = false
        isRecording = false
        isPaused = false
        isFinalizing = false
        errorMessage = message
    }

    private func cleanupSession() {
        isPreparing = false
        isRecording = false
        isPaused = false
        isFinalizing = false
        duration = 0
        accumulatedDuration = 0
        recordingStartedAt = nil
        #if os(iOS)
        currentSegmentID = nil
        #endif
        discardRawRecordings()
        pendingSchedulingState = nil
        completion = nil
        shouldDiscard = false
        shouldPauseAfterCurrentSegment = false
        isViewOnce = false
        enqueueCaptureSessionOperation(shouldRun: false)
    }

    private func discardRawRecordings() {
        for url in rawRecordingURLs {
            TelegramOutgoingFileStaging.shared.discard(fileURL: url)
        }
        rawRecordingURLs.removeAll()
        if let currentRawRecordingURL {
            TelegramOutgoingFileStaging.shared.discard(fileURL: currentRawRecordingURL)
            self.currentRawRecordingURL = nil
        }
    }

    @discardableResult private func enqueueCaptureSessionOperation(shouldRun: Bool) -> Task<Void, Never> {
        let previousTask = captureSessionOperationTask
        let session = captureSession
        let task = Task.detached(priority: shouldRun ? .userInitiated : .utility) {
            await previousTask?.value
            if shouldRun, !session.isRunning {
                session.startRunning()
            } else if !shouldRun, session.isRunning {
                session.stopRunning()
            }
        }
        captureSessionOperationTask = task
        return task
    }
}

// MARK: - TelegramVideoNoteTranscoder

enum TelegramVideoNoteTranscoder {
    static func centeredSquareCrop(in extent: CGRect) -> CGRect {
        let side = min(extent.width, extent.height)
        return CGRect(
            x: extent.midX - side / 2,
            y: extent.midY - side / 2,
            width: side,
            height: side,
        )
    }

    static func exportSquareVideo(sourceURL: URL, outputURL: URL, side: Int) async throws -> Int {
        try await exportSquareVideo(sourceURLs: [sourceURL], outputURL: outputURL, side: side)
    }

    static func exportSquareVideo(sourceURLs: [URL], outputURL: URL, side: Int) async throws -> Int {
        guard !sourceURLs.isEmpty else { throw TelegramVideoNoteRecorderError.exportUnavailable }

        let asset: AVAsset
        if sourceURLs.count == 1, let sourceURL = sourceURLs.first {
            asset = AVURLAsset(url: sourceURL)
        } else {
            let combinedAsset = AVMutableComposition()
            var insertionTime = CMTime.zero
            for sourceURL in sourceURLs {
                let segment = AVURLAsset(url: sourceURL)
                let segmentDuration = try await segment.load(.duration)
                guard segmentDuration.isValid, segmentDuration.isNumeric, segmentDuration > .zero else {
                    continue
                }
                try await combinedAsset.insertTimeRange(
                    CMTimeRange(start: .zero, duration: segmentDuration),
                    of: segment,
                    at: insertionTime,
                )
                insertionTime = insertionTime + segmentDuration
            }
            guard insertionTime > .zero else { throw TelegramVideoNoteRecorderError.exportUnavailable }
            asset = combinedAsset
        }

        let duration = try await asset.load(.duration)
        guard duration.seconds.isFinite, duration.seconds > 0,
              let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality)
        else { throw TelegramVideoNoteRecorderError.exportUnavailable }

        let outputSide = CGFloat(side)
        let composition = try await AVMutableVideoComposition.videoComposition(with: asset) { request in
            let crop = centeredSquareCrop(in: request.sourceImage.extent)
            let scale = outputSide / max(1, crop.width)
            let image = request.sourceImage
                .cropped(to: crop)
                .transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
                .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                .cropped(to: CGRect(x: 0, y: 0, width: outputSide, height: outputSide))
            request.finish(with: image, context: nil)
        }
        composition.renderSize = CGSize(width: outputSide, height: outputSide)
        composition.frameDuration = CMTime(value: 1, timescale: 30)
        exporter.videoComposition = composition
        exporter.shouldOptimizeForNetworkUse = true
        try await exporter.export(to: outputURL, as: .mp4)
        return min(max(1, Int(ceil(duration.seconds))), 60)
    }
}

// MARK: - TelegramVideoNoteCapturePreview

struct TelegramVideoNoteCapturePreview: View {
    let session: AVCaptureSession

    var body: some View {
        TelegramPlatformVideoNoteCapturePreview(session: session)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

#if os(iOS)
private struct TelegramPlatformVideoNoteCapturePreview: UIViewRepresentable {
    final class PreviewView: UIView {
        // MARK: Lifecycle

        override init(frame: CGRect) {
            super.init(frame: frame)
            previewLayer.videoGravity = .resizeAspectFill
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) { fatalError("init(coder:) has not been implemented") }

        // MARK: Internal

        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    let session: AVCaptureSession

    func makeUIView(context _: Context) -> PreviewView {
        PreviewView()
    }

    func updateUIView(_ view: PreviewView, context _: Context) {
        view.previewLayer.session = session
    }
}
#elseif os(macOS)
private struct TelegramPlatformVideoNoteCapturePreview: NSViewRepresentable {
    final class PreviewView: NSView {
        // MARK: Lifecycle

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer = previewLayer
            previewLayer.videoGravity = .resizeAspectFill
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) { fatalError("init(coder:) has not been implemented") }

        // MARK: Internal

        let previewLayer = AVCaptureVideoPreviewLayer()

        override func layout() {
            super.layout()
            previewLayer.frame = bounds
        }
    }

    let session: AVCaptureSession

    func makeNSView(context _: Context) -> PreviewView { PreviewView() }
    func updateNSView(_ view: PreviewView, context _: Context) { view.previewLayer.session = session }
}
#endif

// MARK: - TelegramVideoNoteRecorderError

private enum TelegramVideoNoteRecorderError: Swift.Error {
    case cameraUnavailable
    case captureSessionUnavailable
    case microphoneUnavailable
    case exportUnavailable
}
