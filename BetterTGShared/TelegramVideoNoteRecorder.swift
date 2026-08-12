// TelegramVideoNoteRecorder.swift

@preconcurrency import AVFoundation
import CoreImage
import Observation
import SwiftUI
@preconcurrency import TDLibKit

// MARK: - TelegramVideoNoteRecordingArtifact

struct TelegramVideoNoteRecordingArtifact: Sendable {
    let url: URL
    let thumbnail: TelegramVideoNoteThumbnail?
    let preliminaryUploadFileId: Int?
    let duration: Int
    let length: Int
    let isViewOnce: Bool
}

// MARK: - TelegramVideoNoteDeliveryOptions

struct TelegramVideoNoteDeliveryOptions {
    var schedulingState: MessageSchedulingState?
    var disableNotification = false
    var effectId: TdInt64 = 0
}

// MARK: - TelegramVideoNoteCameraControls

enum TelegramVideoNoteCameraControls {
    static let maximumPreferredZoomFactor: CGFloat = 5
    static let zoomStep: CGFloat = 0.5

    static func clampedZoom(_ proposedZoom: CGFloat, maximumDeviceZoom: CGFloat) -> CGFloat {
        min(max(proposedZoom, 1), min(max(maximumDeviceZoom, 1), maximumPreferredZoomFactor))
    }

    static func usesScreenFlash(
        position: TelegramVideoNoteCameraPosition,
        isFlashEnabled: Bool,
    ) -> Bool {
        position == .front && isFlashEnabled
    }

    static func shouldUseConcurrentCameras(
        isSupported: Bool,
        hardwareCost: Float,
        systemPressureCost: Float,
    ) -> Bool {
        isSupported && hardwareCost <= 1 && systemPressureCost <= 1
    }
}

// MARK: - TelegramVideoNoteCameraPosition

enum TelegramVideoNoteCameraPosition: Sendable {
    case back
    case front

    // MARK: Internal

    var description: String {
        switch self {
        case .back: "Back camera"
        case .front: "Front camera"
        }
    }
}

// MARK: - TelegramVideoNoteRecorder

@MainActor @Observable final class TelegramVideoNoteRecorder: NSObject {
    // MARK: Internal

    private(set) var isPreparing = false
    private(set) var isRecording = false
    private(set) var isPaused = false
    private(set) var isFinalizing = false
    private(set) var duration: TimeInterval = 0
    private(set) var errorMessage: String?
    private(set) var cameraPosition = TelegramVideoNoteCameraPosition.front
    private(set) var canSwitchCamera = false
    private(set) var canUseFlash = false
    private(set) var isFlashEnabled = false
    private(set) var isChangingCamera = false
    private(set) var usesConcurrentCameras = false
    private(set) var zoomFactor: CGFloat = 1
    private(set) var maximumZoomFactor: CGFloat = 1
    private(set) var previewSourceURLs = [URL]()
    var trimStart: Double = 0
    var trimEnd: Double = 0
    var isMuted = false
    var isViewOnce = false

    let captureSession: AVCaptureSession = {
        #if os(iOS)
        if AVCaptureMultiCamSession.isMultiCamSupported {
            return AVCaptureMultiCamSession()
        }
        #endif
        return AVCaptureSession()
    }()

    var canZoomIn: Bool { zoomFactor < maximumZoomFactor }
    var canZoomOut: Bool { zoomFactor > 1 }
    var hasPreview: Bool { isPaused && !previewSourceURLs.isEmpty }

    var normalizedTrimRange: Range<Double> {
        TelegramVideoNoteEditing.normalizedTrimRange(
            start: trimStart,
            end: trimEnd,
            duration: accumulatedDuration,
        )
    }

    var zoomDescription: String {
        "Zoom \(Int((zoomFactor * 100).rounded())) percent"
    }

    var usesScreenFlash: Bool {
        TelegramVideoNoteCameraControls.usesScreenFlash(
            position: cameraPosition,
            isFlashEnabled: isFlashEnabled,
        )
    }

    func start(
        service _: any TelegramService,
        allowsLiveUpload _: Bool = true,
        onFinished: @escaping @MainActor (TelegramVideoNoteRecordingArtifact, TelegramVideoNoteDeliveryOptions) -> Void,
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
            try await startSegment()
        } catch {
            fail("Video recording could not start: \(error.localizedDescription)")
        }
    }

    func pause() {
        guard isRecording, !shouldPauseAfterCurrentSegment else { return }
        updateDuration()
        shouldPauseAfterCurrentSegment = true
        stopTimer()
        assetWriterRecorder.stop()
    }

    func resume() async {
        guard isPaused, !isFinalizing,
              TelegramVideoNoteRecordingLimits.remainingDuration(after: accumulatedDuration) > 0
        else { return }
        previewSourceURLs.removeAll()
        do {
            try await startSegment()
        } catch {
            fail("Video recording could not resume: \(error.localizedDescription)")
            cleanupSession()
        }
    }

    func stop(
        schedulingState: MessageSchedulingState? = nil,
        disableNotification: Bool = false,
        effectId: TdInt64 = 0,
    ) {
        guard isRecording || isPaused else { return }
        pendingDeliveryOptions = TelegramVideoNoteDeliveryOptions(
            schedulingState: schedulingState,
            disableNotification: disableNotification,
            effectId: effectId,
        )
        shouldPauseAfterCurrentSegment = false
        shouldDiscard = false
        updateDuration()
        isRecording = false
        isPaused = false
        isFinalizing = true
        stopTimer()
        if currentSegmentID != nil {
            assetWriterRecorder.stop()
        } else {
            Task { await finalizeRecording() }
        }
    }

    func cancel() {
        guard isPreparing || isRecording || isPaused || isFinalizing || currentRawRecordingURL != nil
            || !rawRecordingURLs.isEmpty
        else { return }
        shouldDiscard = true
        shouldPauseAfterCurrentSegment = false
        completion = nil
        pendingDeliveryOptions = TelegramVideoNoteDeliveryOptions()
        if isFinalizing {
            return
        }
        isPreparing = false
        isRecording = false
        isPaused = false
        isFinalizing = false
        stopTimer()
        assetWriterRecorder.cancel()
        currentSegmentID = nil
        cleanupSession()
    }

    func clearError() {
        errorMessage = nil
    }

    func switchCamera() {
        #if os(iOS)
        guard canSwitchCamera, !isChangingCamera, !isFinalizing else { return }
        isChangingCamera = true
        let target: TelegramVideoNoteCameraPosition = cameraPosition == .front ? .back : .front
        performCameraControl(.switchCamera(target))
        #endif
    }

    func toggleFlash() {
        guard canUseFlash, !isChangingCamera, !isFinalizing else { return }
        performCameraControl(.flash(!isFlashEnabled))
    }

    func zoomIn() {
        setZoomFactor(zoomFactor + TelegramVideoNoteCameraControls.zoomStep)
    }

    func zoomOut() {
        setZoomFactor(zoomFactor - TelegramVideoNoteCameraControls.zoomStep)
    }

    func resetZoom() {
        setZoomFactor(1)
    }

    func normalizeTrimValues() {
        let range = normalizedTrimRange
        trimStart = range.lowerBound
        trimEnd = range.upperBound
    }

    // MARK: Private

    private enum CameraControlOperation: Sendable {
        case flash(Bool)
        case switchCamera(TelegramVideoNoteCameraPosition)
        case zoom(CGFloat)
    }

    private struct CameraControlState: Sendable {
        let position: TelegramVideoNoteCameraPosition
        let canUseFlash: Bool
        let isFlashEnabled: Bool
        let usesConcurrentCameras: Bool
        let zoomFactor: CGFloat
        let maximumZoomFactor: CGFloat
    }

    private enum CameraControlResult: Sendable {
        case failure(String)
        case success(CameraControlState)
    }

    @ObservationIgnored private let assetWriterRecorder = TelegramVideoNoteAssetWriterRecorder()
    @ObservationIgnored private var currentSegmentID: UUID?
    @ObservationIgnored private var completion:
        (@MainActor (TelegramVideoNoteRecordingArtifact, TelegramVideoNoteDeliveryOptions) -> Void)?
    @ObservationIgnored private var configured = false
    @ObservationIgnored private var pendingDeliveryOptions = TelegramVideoNoteDeliveryOptions()
    @ObservationIgnored private var rawRecordingURLs = [URL]()
    @ObservationIgnored private var currentRawRecordingURL: URL?
    @ObservationIgnored private var accumulatedDuration: TimeInterval = 0
    @ObservationIgnored private var recordingStartedAt: Foundation.Date?
    @ObservationIgnored private var shouldDiscard = false
    @ObservationIgnored private var shouldPauseAfterCurrentSegment = false
    @ObservationIgnored private var captureSessionOperationTask: Task<Void, Never>?
    #if os(iOS)
    @ObservationIgnored private var initialScreenBrightness: CGFloat?
    #endif
    @ObservationIgnored private var timerTask: Task<Void, Never>?

    private nonisolated static func applyCameraControl(
        _ operation: CameraControlOperation,
        to session: AVCaptureSession,
        videoOutput: AVCaptureVideoDataOutput?,
        screenFlashEnabled: Bool,
        primaryPosition: TelegramVideoNoteCameraPosition,
        usesConcurrentCameras: Bool,
    ) -> CameraControlResult {
        let expectedPosition: AVCaptureDevice.Position = primaryPosition == .front ? .front : .back
        guard let currentInput = session.inputs
            .compactMap({ $0 as? AVCaptureDeviceInput })
            .first(where: { input in
                input.device.position == expectedPosition
                    && input.ports.contains(where: { $0.mediaType == .video })
            })
        else { return .failure("The active camera is unavailable.") }

        var input = currentInput
        var flashEnabledOverride: Bool?
        switch operation {
        case .switchCamera(let target):
            #if os(iOS)
            let position: AVCaptureDevice.Position = target == .front ? .front : .back
            guard let device = cameraDevice(position: position) else {
                return .failure("The requested camera is unavailable.")
            }
            if usesConcurrentCameras {
                guard let targetInput = session.inputs
                    .compactMap({ $0 as? AVCaptureDeviceInput })
                    .first(where: { $0.device.position == position })
                else { return .failure("The requested camera is unavailable.") }
                if currentInput.device.hasTorch, currentInput.device.torchMode == .on {
                    try? currentInput.device.lockForConfiguration()
                    currentInput.device.torchMode = .off
                    currentInput.device.unlockForConfiguration()
                }
                input = targetInput
                flashEnabledOverride = false
                break
            }
            do {
                let newInput = try AVCaptureDeviceInput(device: device)
                if currentInput.device.hasTorch, currentInput.device.torchMode == .on {
                    try? currentInput.device.lockForConfiguration()
                    currentInput.device.torchMode = .off
                    currentInput.device.unlockForConfiguration()
                }
                session.beginConfiguration()
                session.removeInput(currentInput)
                if session.canAddInput(newInput) {
                    session.addInput(newInput)
                    input = newInput
                } else {
                    session.addInput(currentInput)
                    session.commitConfiguration()
                    return .failure("The camera could not be changed.")
                }
                session.commitConfiguration()
                configureVideoConnection(videoOutput, position: position)
                flashEnabledOverride = false
            } catch {
                return .failure("The camera could not be changed: \(error.localizedDescription)")
            }
            #else
            return .failure("Camera switching isn't available on this platform.")
            #endif
        case .flash(let enabled):
            let device = input.device
            if device.position == .front {
                flashEnabledOverride = enabled
                break
            }
            guard device.hasTorch else {
                return .failure("Flash isn't available for this camera.")
            }
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                if enabled {
                    try device.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel)
                } else {
                    device.torchMode = .off
                }
            } catch {
                return .failure("Flash could not be changed: \(error.localizedDescription)")
            }
        case .zoom(let proposedZoom):
            #if os(iOS)
            let device = input.device
            let zoom = TelegramVideoNoteCameraControls.clampedZoom(
                proposedZoom,
                maximumDeviceZoom: device.activeFormat.videoMaxZoomFactor,
            )
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = zoom
                device.unlockForConfiguration()
            } catch {
                return .failure("Zoom could not be changed: \(error.localizedDescription)")
            }
            #else
            return .failure("Camera zoom isn't available on this platform.")
            #endif
        }

        let device = input.device
        #if os(iOS)
        let maximumZoom = TelegramVideoNoteCameraControls.clampedZoom(
            device.activeFormat.videoMaxZoomFactor,
            maximumDeviceZoom: device.activeFormat.videoMaxZoomFactor,
        )
        return .success(.init(
            position: device.position == .back ? .back : .front,
            canUseFlash: device.position == .front || device.hasTorch,
            isFlashEnabled: device.position == .front
                ? (flashEnabledOverride ?? screenFlashEnabled)
                : device.torchMode == .on,
            usesConcurrentCameras: usesConcurrentCameras,
            zoomFactor: TelegramVideoNoteCameraControls.clampedZoom(
                device.videoZoomFactor,
                maximumDeviceZoom: maximumZoom,
            ),
            maximumZoomFactor: maximumZoom,
        ))
        #else
        return .success(.init(
            position: .front,
            canUseFlash: false,
            isFlashEnabled: false,
            usesConcurrentCameras: false,
            zoomFactor: 1,
            maximumZoomFactor: 1,
        ))
        #endif
    }

    #if os(iOS)
    private nonisolated static func cameraDevice(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
    }

    private nonisolated static func addVideoConnection(
        input: AVCaptureDeviceInput,
        output: AVCaptureVideoDataOutput,
        to session: AVCaptureMultiCamSession,
    ) throws -> AVCaptureConnection {
        guard session.canAddInput(input), session.canAddOutput(output) else {
            throw TelegramVideoNoteRecorderError.captureSessionUnavailable
        }
        session.addInputWithNoConnections(input)
        session.addOutputWithNoConnections(output)
        guard let port = input.ports.first(where: { $0.mediaType == .video }) else {
            session.removeOutput(output)
            session.removeInput(input)
            throw TelegramVideoNoteRecorderError.cameraUnavailable
        }
        let connection = AVCaptureConnection(inputPorts: [port], output: output)
        guard session.canAddConnection(connection) else {
            session.removeOutput(output)
            session.removeInput(input)
            throw TelegramVideoNoteRecorderError.captureSessionUnavailable
        }
        session.addConnection(connection)
        return connection
    }

    private nonisolated static func configureConcurrentCameraFormat(_ device: AVCaptureDevice) throws {
        let preferredMaximumPixels = Int32(1280 * 720)
        let candidates = device.formats.compactMap { format -> (AVCaptureDevice.Format, Int32)? in
            guard format.isMultiCamSupported,
                  format.videoSupportedFrameRateRanges.contains(where: { $0.maxFrameRate >= 24 })
            else { return nil }
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            return (format, dimensions.width * dimensions.height)
        }
        guard let selected = candidates
            .filter({ $0.1 <= preferredMaximumPixels })
            .max(by: { $0.1 < $1.1 })
            ?? candidates.min(by: { $0.1 < $1.1 })
        else { throw TelegramVideoNoteRecorderError.cameraUnavailable }

        let maximumFrameRate = selected.0
.videoSupportedFrameRateRanges
            .map(\.maxFrameRate)
            .max() ?? 24
        let frameRate = min(30, maximumFrameRate)
        try device.lockForConfiguration()
        device.activeFormat = selected.0
        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(frameRate.rounded(.down)))
        device.activeVideoMinFrameDuration = frameDuration
        device.activeVideoMaxFrameDuration = frameDuration
        device.unlockForConfiguration()
    }

    private nonisolated static func configureVideoConnection(
        _ output: AVCaptureVideoDataOutput?,
        position: AVCaptureDevice.Position,
    ) {
        guard let connection = output?.connection(with: .video) else { return }
        configureVideoConnection(connection, position: position)
    }

    private nonisolated static func configureVideoConnection(
        _ connection: AVCaptureConnection,
        position: AVCaptureDevice.Position,
    ) {
        if connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = position == .front
        }
    }
    #endif

    #if os(iOS)
    private func configureAudioSessionForRecording() throws {
        let audioSession = AVAudioSession.sharedInstance()
        // No `.mixWithOthers`, ever - see `Media.setAudioSessionRecord()`'s matching comment.
        // Letting other audio keep playing through the speaker while recording risks it bleeding
        // into the recorded video note itself.
        let options: AVAudioSession.CategoryOptions = [
            .allowBluetoothHFP,
            .defaultToSpeaker,
            .overrideMutedMicrophoneInterruption,
        ]
        try audioSession.setCategory(
            .playAndRecord,
            mode: .videoRecording,
            policy: .default,
            options: options,
        )
        // Documented to suppress system sounds/haptics for the duration of the recording.
        try audioSession.setAllowHapticsAndSystemSoundsDuringRecording(false)
        try audioSession.setActive(true)
    }
    #endif

    private func configureSessionIfNeeded() throws {
        guard !configured else { return }
        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }
        #if os(iOS)
        let supportsSessionPreset = !(captureSession is AVCaptureMultiCamSession)
        #else
        let supportsSessionPreset = true
        #endif
        if supportsSessionPreset, captureSession.canSetSessionPreset(.high) {
            captureSession.sessionPreset = .high
        }

        #if os(iOS)
        let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            ?? AVCaptureDevice.default(for: .video)
        guard let videoDevice else { throw TelegramVideoNoteRecorderError.cameraUnavailable }
        let videoInput = try AVCaptureDeviceInput(device: videoDevice)
        if let multiCamSession = captureSession as? AVCaptureMultiCamSession {
            try Self.configureConcurrentCameraFormat(videoDevice)
            let primaryConnection = try Self.addVideoConnection(
                input: videoInput,
                output: assetWriterRecorder.videoOutput,
                to: multiCamSession,
            )
            Self.configureVideoConnection(primaryConnection, position: videoDevice.position)

            if let backDevice = Self.cameraDevice(position: .back),
               let additionalInput = try? AVCaptureDeviceInput(device: backDevice),
               (try? Self.configureConcurrentCameraFormat(backDevice)) != nil,
               let additionalConnection = try? Self.addVideoConnection(
                   input: additionalInput,
                   output: assetWriterRecorder.additionalVideoOutput,
                   to: multiCamSession,
               )
            {
                Self.configureVideoConnection(additionalConnection, position: backDevice.position)
                if TelegramVideoNoteCameraControls.shouldUseConcurrentCameras(
                    isSupported: true,
                    hardwareCost: multiCamSession.hardwareCost,
                    systemPressureCost: multiCamSession.systemPressureCost,
                ) {
                    usesConcurrentCameras = true
                } else {
                    multiCamSession.removeConnection(additionalConnection)
                    multiCamSession.removeOutput(assetWriterRecorder.additionalVideoOutput)
                    multiCamSession.removeInput(additionalInput)
                }
            }
        } else {
            guard captureSession.canAddInput(videoInput) else {
                throw TelegramVideoNoteRecorderError.cameraUnavailable
            }
            captureSession.addInput(videoInput)
            guard captureSession.canAddOutput(assetWriterRecorder.videoOutput) else {
                throw TelegramVideoNoteRecorderError.captureSessionUnavailable
            }
            captureSession.addOutput(assetWriterRecorder.videoOutput)
            Self.configureVideoConnection(assetWriterRecorder.videoOutput, position: videoDevice.position)
        }

        guard let audioDevice = AVCaptureDevice.default(for: .audio) else {
            throw TelegramVideoNoteRecorderError.microphoneUnavailable
        }
        let audioInput = try AVCaptureDeviceInput(device: audioDevice)
        guard captureSession.canAddInput(audioInput) else {
            throw TelegramVideoNoteRecorderError.microphoneUnavailable
        }
        captureSession.addInput(audioInput)
        guard captureSession.canAddOutput(assetWriterRecorder.audioOutput) else {
            throw TelegramVideoNoteRecorderError.captureSessionUnavailable
        }
        captureSession.addOutput(assetWriterRecorder.audioOutput)
        captureSession.automaticallyConfiguresApplicationAudioSession = false
        assetWriterRecorder.selectCamera(position: videoDevice.position)
        #else
        let videoDevice = AVCaptureDevice.default(for: .video)
        guard let videoDevice else { throw TelegramVideoNoteRecorderError.cameraUnavailable }
        let videoInput = try AVCaptureDeviceInput(device: videoDevice)
        guard captureSession.canAddInput(videoInput) else {
            throw TelegramVideoNoteRecorderError.cameraUnavailable
        }
        captureSession.addInput(videoInput)
        guard captureSession.canAddOutput(assetWriterRecorder.videoOutput) else {
            throw TelegramVideoNoteRecorderError.captureSessionUnavailable
        }
        captureSession.addOutput(assetWriterRecorder.videoOutput)

        guard let audioDevice = AVCaptureDevice.default(for: .audio) else {
            throw TelegramVideoNoteRecorderError.microphoneUnavailable
        }
        let audioInput = try AVCaptureDeviceInput(device: audioDevice)
        guard captureSession.canAddInput(audioInput) else {
            throw TelegramVideoNoteRecorderError.microphoneUnavailable
        }
        captureSession.addInput(audioInput)
        guard captureSession.canAddOutput(assetWriterRecorder.audioOutput) else {
            throw TelegramVideoNoteRecorderError.captureSessionUnavailable
        }
        captureSession.addOutput(assetWriterRecorder.audioOutput)
        assetWriterRecorder.selectCamera(position: videoDevice.position)
        #endif
        configured = true
        updateCameraControlState(for: videoDevice)
    }

    private func updateCameraControlState(for device: AVCaptureDevice) {
        #if os(iOS)
        cameraPosition = device.position == .back ? .back : .front
        canSwitchCamera = Self.cameraDevice(position: .front) != nil
            && Self.cameraDevice(position: .back) != nil
        canUseFlash = device.position == .front || device.hasTorch
        #else
        cameraPosition = .front
        canSwitchCamera = false
        canUseFlash = false
        isFlashEnabled = device.torchMode == .on
        zoomFactor = 1
        maximumZoomFactor = 1
        #endif
        #if os(iOS)
        isFlashEnabled = device.torchMode == .on
        maximumZoomFactor = TelegramVideoNoteCameraControls.clampedZoom(
            device.activeFormat.videoMaxZoomFactor,
            maximumDeviceZoom: device.activeFormat.videoMaxZoomFactor,
        )
        zoomFactor = TelegramVideoNoteCameraControls.clampedZoom(
            device.videoZoomFactor,
            maximumDeviceZoom: maximumZoomFactor,
        )
        #endif
    }

    private func setZoomFactor(_ proposedZoom: CGFloat) {
        guard !isChangingCamera, !isFinalizing else { return }
        let zoom = TelegramVideoNoteCameraControls.clampedZoom(
            proposedZoom,
            maximumDeviceZoom: maximumZoomFactor,
        )
        guard zoom != zoomFactor else { return }
        performCameraControl(.zoom(zoom))
    }

    private func performCameraControl(_ operation: CameraControlOperation) {
        let previousTask = captureSessionOperationTask
        let session = captureSession
        let screenFlashEnabled = usesScreenFlash
        let primaryPosition = cameraPosition
        let concurrentCamerasEnabled = usesConcurrentCameras
        let videoOutput: AVCaptureVideoDataOutput? = assetWriterRecorder.videoOutput
        let operationTask = Task.detached(priority: .userInitiated) {
            await previousTask?.value
            return Self.applyCameraControl(
                operation,
                to: session,
                videoOutput: videoOutput,
                screenFlashEnabled: screenFlashEnabled,
                primaryPosition: primaryPosition,
                usesConcurrentCameras: concurrentCamerasEnabled,
            )
        }
        captureSessionOperationTask = Task {
            _ = await operationTask.value
        }
        Task { [weak self] in
            let result = await operationTask.value
            guard let self else { return }
            isChangingCamera = false
            switch result {
            case .failure(let message):
                errorMessage = message
            case .success(let state):
                cameraPosition = state.position
                canUseFlash = state.canUseFlash
                isFlashEnabled = state.isFlashEnabled
                usesConcurrentCameras = state.usesConcurrentCameras
                zoomFactor = state.zoomFactor
                maximumZoomFactor = state.maximumZoomFactor
                #if os(iOS)
                assetWriterRecorder.selectCamera(
                    position: state.position == .front ? .front : .back,
                )
                #endif
                updateScreenBrightness()
            }
        }
    }

    private func updateScreenBrightness() {
        #if os(iOS)
        let windowScenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let screen = windowScenes.first(where: { $0.activationState == .foregroundActive })?.screen
            ?? windowScenes.first?.screen
        else { return }
        if usesScreenFlash {
            if initialScreenBrightness == nil {
                initialScreenBrightness = screen.brightness
            }
            screen.brightness = 1
        } else if let initialScreenBrightness {
            self.initialScreenBrightness = nil
            screen.brightness = initialScreenBrightness
        }
        #endif
    }

    private func startSegment() async throws {
        let remainingDuration = TelegramVideoNoteRecordingLimits.remainingDuration(after: accumulatedDuration)
        guard remainingDuration > 0 else {
            isPaused = false
            isFinalizing = true
            Task { await finalizeRecording() }
            return
        }

        let url = TelegramOutgoingFileStaging.shared.videoNoteAssetWriterFileURL()
        currentRawRecordingURL = url
        recordingStartedAt = .now
        shouldPauseAfterCurrentSegment = false
        isPaused = false
        isRecording = true
        do {
            let segmentID = try await assetWriterRecorder.start(
                to: url,
                completion: { [weak self] id, result in
                    await self?.finishAssetWriterSegment(id: id, result: result)
                },
            )
            // `stop()`/`cancel()` may have run while the writer was starting up (this is an
            // await point, so the recorder is reentrant here). If they did, `isRecording` is
            // already false; tear down the segment we just created instead of adopting it.
            guard isRecording else {
                assetWriterRecorder.cancel()
                return
            }
            currentSegmentID = segmentID
        } catch {
            currentRawRecordingURL = nil
            recordingStartedAt = nil
            isRecording = false
            throw error
        }
        startTimer()
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
                preparePreview()
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
                preparePreview()
                return
            }

            isRecording = false
            isPaused = false
            isFinalizing = true
            await finalizeRecording()
        }
    }

    private func finalizeRecording() async {
        guard !rawRecordingURLs.isEmpty else {
            fail("Video message could not be prepared because no recording was captured.")
            cleanupSession()
            return
        }
        guard TelegramVideoNoteEditing.isSendableDuration(accumulatedDuration) else {
            fail("Video messages must be at least one second long.")
            cleanupSession()
            return
        }

        let trimRange = normalizedTrimRange
        if TelegramVideoNoteRecordedFileReusePolicy.canReuse(
            segmentCount: rawRecordingURLs.count,
            trimRange: trimRange,
            duration: accumulatedDuration,
        ), let sourceURL = rawRecordingURLs.first {
            let thumbnailURL = TelegramOutgoingFileStaging.shared.videoNoteThumbnailFileURL()
            let thumbnail = try? await TelegramVideoNoteEditing.generateThumbnail(
                videoURL: sourceURL,
                outputURL: thumbnailURL,
            )
            if thumbnail == nil {
                TelegramOutgoingFileStaging.shared.discard(fileURL: thumbnailURL)
            }
            guard !shouldDiscard else {
                TelegramOutgoingFileStaging.shared.discard(fileURL: sourceURL)
                cleanupSession()
                return
            }

            rawRecordingURLs.removeAll()
            let artifact = TelegramVideoNoteRecordingArtifact(
                url: sourceURL,
                thumbnail: thumbnail,
                preliminaryUploadFileId: nil,
                duration: min(max(1, Int(ceil(trimRange.upperBound - trimRange.lowerBound))), 60),
                length: 480,
                isViewOnce: isViewOnce,
            )
            let deliveryOptions = pendingDeliveryOptions
            let completion = completion
            cleanupSession()
            completion?(artifact, deliveryOptions)
            return
        }

        let outputURL = TelegramOutgoingFileStaging.shared.videoNoteFileURL()
        let thumbnailURL = TelegramOutgoingFileStaging.shared.videoNoteThumbnailFileURL()
        do {
            let duration = try await TelegramVideoNoteTranscoder.exportSquareVideo(
                sourceURLs: rawRecordingURLs,
                outputURL: outputURL,
                side: 480,
                trimRange: normalizedTrimRange,
            )
            let thumbnail = try? await TelegramVideoNoteEditing.generateThumbnail(
                videoURL: outputURL,
                outputURL: thumbnailURL,
            )
            if thumbnail == nil {
                TelegramOutgoingFileStaging.shared.discard(fileURL: thumbnailURL)
            }
            discardRawRecordings()
            if shouldDiscard {
                TelegramOutgoingFileStaging.shared.discard(fileURL: outputURL)
                if let thumbnail {
                    TelegramOutgoingFileStaging.shared.discard(fileURL: thumbnail.url)
                }
                cleanupSession()
                return
            }
            let artifact = TelegramVideoNoteRecordingArtifact(
                url: outputURL,
                thumbnail: thumbnail,
                preliminaryUploadFileId: nil,
                duration: duration,
                length: 480,
                isViewOnce: isViewOnce,
            )
            let deliveryOptions = pendingDeliveryOptions
            let completion = completion
            cleanupSession()
            completion?(artifact, deliveryOptions)
        } catch {
            discardRawRecordings()
            TelegramOutgoingFileStaging.shared.discard(fileURL: outputURL)
            TelegramOutgoingFileStaging.shared.discard(fileURL: thumbnailURL)
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
        if isFlashEnabled {
            performCameraControl(.flash(false))
        }
        isPreparing = false
        isRecording = false
        isPaused = false
        isFinalizing = false
        duration = 0
        accumulatedDuration = 0
        previewSourceURLs.removeAll()
        trimStart = 0
        trimEnd = 0
        isMuted = false
        recordingStartedAt = nil
        currentSegmentID = nil
        discardRawRecordings()
        pendingDeliveryOptions = TelegramVideoNoteDeliveryOptions()
        completion = nil
        shouldDiscard = false
        shouldPauseAfterCurrentSegment = false
        isViewOnce = false
        updateScreenBrightness()
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

    private func preparePreview() {
        previewSourceURLs = rawRecordingURLs
        trimStart = 0
        trimEnd = accumulatedDuration
        isMuted = true
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

    static func exportSquareVideo(
        sourceURLs: [URL],
        outputURL: URL,
        side: Int,
        trimRange: Range<Double>? = nil,
    ) async throws -> Int {
        let asset = try await TelegramVideoNoteEditing.combinedAsset(sourceURLs: sourceURLs)

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
        let effectiveTrimRange = TelegramVideoNoteEditing.normalizedTrimRange(
            start: trimRange?.lowerBound ?? 0,
            end: trimRange?.upperBound ?? duration.seconds,
            duration: duration.seconds,
        )
        exporter.timeRange = CMTimeRange(
            start: CMTime(seconds: effectiveTrimRange.lowerBound, preferredTimescale: 600),
            duration: CMTime(
                seconds: effectiveTrimRange.upperBound - effectiveTrimRange.lowerBound,
                preferredTimescale: 600,
            ),
        )
        exporter.shouldOptimizeForNetworkUse = true
        try await exporter.export(to: outputURL, as: .mp4)
        return min(max(1, Int(ceil(effectiveTrimRange.upperBound - effectiveTrimRange.lowerBound))), 60)
    }
}

// MARK: - TelegramVideoNoteCapturePreview

struct TelegramVideoNoteCapturePreview: View {
    let session: AVCaptureSession
    let position: TelegramVideoNoteCameraPosition

    var body: some View {
        TelegramPlatformVideoNoteCapturePreview(session: session, position: position)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

#if os(iOS)
private struct TelegramPlatformVideoNoteCapturePreview: UIViewRepresentable {
    final class PreviewView: UIView {
        // MARK: Lifecycle

        init(session: AVCaptureSession) {
            self.session = session
            self.previewLayer = AVCaptureVideoPreviewLayer(sessionWithNoConnection: session)
            super.init(frame: .zero)
            previewLayer.videoGravity = .resizeAspectFill
            layer.addSublayer(previewLayer)
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) { fatalError("init(coder:) has not been implemented") }

        // MARK: Internal

        let previewLayer: AVCaptureVideoPreviewLayer

        override func layoutSubviews() {
            super.layoutSubviews()
            previewLayer.frame = bounds
        }

        func update(position: TelegramVideoNoteCameraPosition) {
            guard currentPosition != position || previewLayer.connection == nil else { return }
            let devicePosition: AVCaptureDevice.Position = position == .front ? .front : .back
            guard let port = session.inputs
                .compactMap({ $0 as? AVCaptureDeviceInput })
                .first(where: { $0.device.position == devicePosition })?
                .ports
                .first(where: { $0.mediaType == .video })
            else { return }

            session.beginConfiguration()
            if let currentConnection = previewLayer.connection {
                session.removeConnection(currentConnection)
            }
            let connection = AVCaptureConnection(inputPort: port, videoPreviewLayer: previewLayer)
            if session.canAddConnection(connection) {
                session.addConnection(connection)
                if connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90
                }
                if connection.isVideoMirroringSupported {
                    connection.automaticallyAdjustsVideoMirroring = false
                    connection.isVideoMirrored = position == .front
                }
                currentPosition = position
            }
            session.commitConfiguration()
        }

        func disconnect() {
            guard let connection = previewLayer.connection else { return }
            session.beginConfiguration()
            session.removeConnection(connection)
            session.commitConfiguration()
            currentPosition = nil
        }

        // MARK: Private

        private let session: AVCaptureSession
        private var currentPosition: TelegramVideoNoteCameraPosition?
    }

    let session: AVCaptureSession
    let position: TelegramVideoNoteCameraPosition

    static func dismantleUIView(_ view: PreviewView, coordinator _: Void) {
        view.disconnect()
    }

    func makeUIView(context _: Context) -> PreviewView {
        PreviewView(session: session)
    }

    func updateUIView(_ view: PreviewView, context _: Context) {
        view.update(position: position)
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
    let position: TelegramVideoNoteCameraPosition

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
