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
    private(set) var isFinalizing = false
    private(set) var duration: TimeInterval = 0
    private(set) var errorMessage: String?
    var isViewOnce = false

    let captureSession = AVCaptureSession()

    func start(
        onFinished: @escaping @MainActor (TelegramVideoNoteRecordingArtifact, MessageSchedulingState?) -> Void,
    ) async {
        guard !isPreparing, !isRecording, !isFinalizing else { return }
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
            try configureSessionIfNeeded()
            let session = captureSession
            await Task.detached(priority: .userInitiated) {
                if !session.isRunning {
                    session.startRunning()
                }
            }.value

            let url = TelegramOutgoingFileStaging.shared.videoNoteFileURL(isRawRecording: true)
            rawRecordingURL = url
            recordingStartedAt = Foundation.Date()
            duration = 0
            isPreparing = false
            isRecording = true
            output.maxRecordedDuration = CMTime(seconds: 60, preferredTimescale: 600)
            output.startRecording(to: url, recordingDelegate: self)
            startTimer()
        } catch {
            fail("Video recording could not start: \(error.localizedDescription)")
        }
    }

    func stop(schedulingState: MessageSchedulingState? = nil) {
        guard isRecording else { return }
        pendingSchedulingState = schedulingState
        shouldDiscard = false
        isRecording = false
        isFinalizing = true
        stopTimer()
        output.stopRecording()
    }

    func cancel() {
        guard isPreparing || isRecording || isFinalizing || rawRecordingURL != nil else { return }
        shouldDiscard = true
        completion = nil
        pendingSchedulingState = nil
        if isFinalizing {
            return
        }
        isPreparing = false
        isRecording = false
        isFinalizing = false
        stopTimer()
        if output.isRecording {
            output.stopRecording()
        } else {
            cleanupSession()
        }
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
        Task { @MainActor [weak self] in
            await self?.finishRecording(at: outputFileURL, error: error)
        }
    }

    // MARK: Private

    @ObservationIgnored private let output = AVCaptureMovieFileOutput()
    @ObservationIgnored private var completion:
        (@MainActor (TelegramVideoNoteRecordingArtifact, MessageSchedulingState?) -> Void)?
    @ObservationIgnored private var configured = false
    @ObservationIgnored private var pendingSchedulingState: MessageSchedulingState?
    @ObservationIgnored private var rawRecordingURL: URL?
    @ObservationIgnored private var recordingStartedAt: Foundation.Date?
    @ObservationIgnored private var shouldDiscard = false
    @ObservationIgnored private var timerTask: Task<Void, Never>?

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
        guard captureSession.canAddInput(audioInput), captureSession.canAddOutput(output) else {
            throw TelegramVideoNoteRecorderError.microphoneUnavailable
        }
        captureSession.addInput(audioInput)
        captureSession.addOutput(output)
        #if os(iOS)
        if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        #endif
        configured = true
    }

    private func startTimer() {
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self, isRecording, let recordingStartedAt else { return }
                duration = min(60, Foundation.Date().timeIntervalSince(recordingStartedAt))
            }
        }
    }

    private func stopTimer() {
        timerTask?.cancel()
        timerTask = nil
    }

    private func finishRecording(at rawURL: URL, error: (any Swift.Error)?) async {
        stopTimer()
        isPreparing = false
        isRecording = false
        isFinalizing = !shouldDiscard
        if shouldDiscard {
            TelegramOutgoingFileStaging.shared.discard(fileURL: rawURL)
            cleanupSession()
            return
        }
        if let error, !FileManager.default.fileExists(atPath: rawURL.path) {
            fail("Video recording failed: \(error.localizedDescription)")
            cleanupSession()
            return
        }

        let outputURL = TelegramOutgoingFileStaging.shared.videoNoteFileURL()
        do {
            let duration = try await TelegramVideoNoteTranscoder.exportSquareVideo(
                sourceURL: rawURL,
                outputURL: outputURL,
                side: 480,
            )
            TelegramOutgoingFileStaging.shared.discard(fileURL: rawURL)
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
            TelegramOutgoingFileStaging.shared.discard(fileURL: rawURL)
            TelegramOutgoingFileStaging.shared.discard(fileURL: outputURL)
            fail("Video message could not be prepared: \(error.localizedDescription)")
            cleanupSession()
        }
    }

    private func fail(_ message: String) {
        isPreparing = false
        isRecording = false
        isFinalizing = false
        errorMessage = message
    }

    private func cleanupSession() {
        isPreparing = false
        isRecording = false
        isFinalizing = false
        duration = 0
        recordingStartedAt = nil
        rawRecordingURL = nil
        pendingSchedulingState = nil
        completion = nil
        shouldDiscard = false
        isViewOnce = false
        let session = captureSession
        Task.detached(priority: .utility) {
            if session.isRunning {
                session.stopRunning()
            }
        }
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
        let asset = AVURLAsset(url: sourceURL)
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
    case microphoneUnavailable
    case exportUnavailable
}
