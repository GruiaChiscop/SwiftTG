// TelegramCallSession.swift

import AVFoundation
import Combine
import CoreTelephony
import Network
import Observation
import TDLibKit
@preconcurrency import TgVoipWebrtc
import UIKit

// MARK: - CallProtocol + @retroactive @unchecked Sendable

/// TDLibKit's generated models don't declare `Sendable`; `CallProtocol` is a value made entirely
/// from Sendable fields and crosses the actor boundary into TelegramService's async RPC methods.
extension CallProtocol: @retroactive @unchecked Sendable {}

// MARK: - TelegramCallSession

/// Bridges TDLib's call state/signaling to the vendored tgcalls engine. TelegramCallEngine owns the
/// strict tgcalls queue confinement.
@MainActor
@Observable final class TelegramCallSession {
    // MARK: Lifecycle

    init(service: any TelegramService) {
        self.service = service
        service.callPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] call in self?.handle(call: call) }
            .store(in: &cancellables)
        service.callSignalingDataPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] data in self?.handleSignaling(data) }
            .store(in: &cancellables)
        CallKitManager.shared
            .audioSessionActivePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] active in self?.applyAudioSessionActive(active) }
            .store(in: &cancellables)

        let notificationCenter = NotificationCenter.default
        notificationCenter.publisher(for: AVAudioSession.routeChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in self?.handleAudioRouteChange(notification) }
            .store(in: &cancellables)
        notificationCenter.publisher(for: AVAudioSession.availableInputsChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshAudioRoutes() }
            .store(in: &cancellables)
        notificationCenter.publisher(for: AVAudioSession.interruptionNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in self?.handleAudioInterruption(notification) }
            .store(in: &cancellables)
        notificationCenter.publisher(for: AVAudioSession.mediaServicesWereLostNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.handleMediaServicesLost() }
            .store(in: &cancellables)
        notificationCenter.publisher(for: AVAudioSession.mediaServicesWereResetNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.handleMediaServicesReset() }
            .store(in: &cancellables)
        notificationCenter.publisher(for: UIDevice.proximityStateDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateProximityMonitoring() }
            .store(in: &cancellables)
        notificationCenter.publisher(for: UIDevice.batteryLevelDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshLowBatteryState() }
            .store(in: &cancellables)
        notificationCenter.publisher(for: UIDevice.batteryStateDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshLowBatteryState() }
            .store(in: &cancellables)
        notificationCenter.publisher(for: .CTServiceRadioAccessTechnologyDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshNetworkKind() }
            .store(in: &cancellables)

        refreshAudioRoutes()

        networkMonitor.pathUpdateHandler = { [weak self] path in
            let usesCellular = path.usesInterfaceType(.cellular)
            Task { @MainActor [weak self] in
                self?.usesCellularNetwork = usesCellular
                self?.refreshNetworkKind()
            }
        }
        networkMonitor.start(queue: networkMonitorQueue)
    }

    // MARK: Internal

    enum EndReason: Sendable {
        case failed
        case remoteEnded
        case unanswered
    }

    struct AudioRoute: Identifiable, Equatable, Sendable {
        enum Kind: Equatable, Sendable {
            case builtIn
            case speaker
            case wired
            case bluetooth
            case external
        }

        static let builtIn = AudioRoute(id: "builtin", name: "iPhone", kind: .builtIn)
        static let speaker = AudioRoute(id: "speaker", name: "Speaker", kind: .speaker)

        let id: String
        let name: String
        let kind: Kind
    }

    static let shared = TelegramCallSession(service: TDLib.shared.service)

    private(set) var activeCall: Call?

    private(set) var engineState: TelegramCallEngine.State?
    private(set) var isMuted = false
    private(set) var isSpeakerOn = false
    private(set) var availableAudioRoutes: [AudioRoute] = [.builtIn, .speaker]
    private(set) var selectedAudioRoute = AudioRoute.builtIn
    private(set) var connectedAt: Foundation.Date?
    private(set) var encryptionEmojis = [String]()
    private(set) var isCallViewMinimized = false
    private(set) var remoteAudioState = TelegramCallEngine.RemoteAudioState.active
    private(set) var remoteVideoState = TelegramCallEngine.RemoteVideoState.inactive
    private(set) var remoteBatteryLevel = TelegramCallEngine.RemoteBatteryLevel.normal
    private(set) var signalBars: Int?
    private(set) var groupCallCoordinator: TelegramGroupCallCoordinator?
    private(set) var isUpgradingToConference = false
    private(set) var isInvitingConferenceParticipant = false
    private(set) var isLocalVideoEnabled = false
    private(set) var localVideoView: UIView?
    private(set) var cameraPreviewView: UIView?
    private(set) var remoteVideoView: UIView?
    private(set) var pictureInPictureSourceView: UIView?
    private(set) var isUsingFrontCamera = true
    private(set) var showsCameraPreview = false
    private(set) var isScreenSharing = false
    var showsCameraPermissionAlert = false
    var pendingCallRating: CallRatingRequest?

    var onIncomingCall: ((Call) -> Void)?
    var onCallConnected: (() -> Void)?
    var onCallEnded: ((EndReason) -> Void)?

    /// The native CallKit UI remains the sole incoming-answer surface while the call is pending.
    var shouldShowCallView: Bool {
        guard let activeCall else { return false }
        if !activeCall.isOutgoing, case .callStatePending = activeCall.state {
            return false
        }
        return !isCallViewMinimized
    }

    var shouldShowMinimizedCallBar: Bool { activeCall != nil && isCallViewMinimized }

    var isConferenceCall: Bool { groupCallCoordinator != nil }

    var showsConferenceCallUI: Bool { conferenceHasReplacedPrivateCall && conferenceAudioWasMoved }

    var conferenceParticipants: [GroupCallParticipant] {
        guard let groupCallCoordinator else { return [] }
        return groupCallCoordinator.participants.values.sorted { $0.order > $1.order }
    }

    var pendingConferenceInvitedUserIds: [Int64] {
        let joinedUserIds = Set(conferenceParticipants.compactMap { participant -> Int64? in
            guard case .messageSenderUser(let user) = participant.participantId else { return nil }
            return user.userId
        })
        return conferenceInvitedUserIds.subtracting(joinedUserIds).sorted()
    }

    var conferenceParticipantCount: Int {
        max(groupCallCoordinator?.groupCall?.participantCount ?? 0, conferenceParticipants.count)
    }

    var conferenceSpeakingParticipantIds: Set<MessageSender> {
        guard let groupCallCoordinator else { return [] }
        return Set(conferenceParticipants.compactMap { participant -> MessageSender? in
            let audioSourceId = participant.isCurrentUser
                ? 0
                : UInt32(bitPattern: Int32(truncatingIfNeeded: participant.audioSourceId))
            guard participant.isSpeaking || groupCallCoordinator.speakingAudioSourceIds.contains(audioSourceId) else {
                return nil
            }
            return participant.participantId
        })
    }

    var canUpgradeToConference: Bool {
        guard !isUpgradingToConference,
              groupCallCoordinator == nil,
              engineState == .connected,
              case .callStateReady(let ready) = activeCall?.state
        else { return false }
        return ready.isGroupCallSupported
    }

    var canAddConferenceParticipant: Bool {
        if canUpgradeToConference {
            return true
        }
        guard !isUpgradingToConference,
              !isInvitingConferenceParticipant,
              conferenceHasReplacedPrivateCall,
              let groupCallCoordinator,
              case .connected = groupCallCoordinator.state
        else { return false }
        return true
    }

    var excludedConferenceParticipantUserIds: Set<Int64> {
        var userIds = conferenceInvitedUserIds
        if let userId = activeCall?.userId {
            userIds.insert(userId)
        }
        if let participants = groupCallCoordinator?.participants {
            for participantId in participants.keys {
                if case .messageSenderUser(let user) = participantId {
                    userIds.insert(user.userId)
                }
            }
        }
        return userIds
    }

    var canToggleVideo: Bool {
        guard groupCallCoordinator == nil, !isRequestingVideo, !showsCameraPreview else { return false }
        return isLocalVideoEnabled || engineState == .connected || engineState == .reconnecting
    }

    /// tgcalls configures the category/mode/options CallKit will later activate. This has to run
    /// before reporting or requesting a CallKit call, matching Telegram-iOS's ordering.
    static func prepareAudioSession() {
        SharedCallAudioDevice.setupAudioSession()
    }

    func startCall(userId: Int64, isVideo: Bool, completion: @escaping (Bool) -> Void = { _ in }) {
        Task { [weak self] in
            guard let self else {
                completion(false)
                return
            }
            do {
                _ = try await service.createCall(isVideo: isVideo, protocol: Self.ourProtocol(), userId: userId)
                completion(true)
            } catch {
                log("Error creating call: \(error)")
                completion(false)
            }
        }
    }

    func answer() {
        answerActiveCall()
    }

    /// CallKit can deliver Answer before TDLib publishes the call after a cold VoIP wake. Keep the
    /// action and apply it to the first real call rather than fulfilling and losing it.
    func answerFromSystem() {
        guard activeCall != nil else {
            pendingSystemAction = .answer
            log("[Call] deferring system Answer until TDLib publishes the call")
            return
        }
        answerActiveCall()
    }

    func end() {
        CallKitManager.shared.requestEndCall()
    }

    /// The same cold-wake race applies to End; End takes precedence over an earlier Answer.
    func endFromSystem(completion: @escaping (Bool) -> Void = { _ in }) {
        if let groupCallCoordinator {
            if conferenceHasReplacedPrivateCall {
                groupCallCoordinator.leave(endForEveryone: false)
                completion(true)
                return
            }
            resetConferencePreparation(groupCallCoordinator)
        }
        guard activeCall != nil else {
            pendingSystemAction = .end
            log("[Call] deferring system End until TDLib publishes the call")
            completion(true)
            return
        }
        endActiveCall(isDisconnected: false, completion: completion)
    }

    func cancelPendingSystemAction() {
        pendingSystemAction = nil
    }

    func toggleMute() {
        CallKitManager.shared.requestSetMuted(!isMuted)
    }

    func setMuted(_ muted: Bool) {
        isMuted = muted
        engine.setMuted(muted)
        groupCallCoordinator?.setMuted(muted)
    }

    func upgradeToConference(inviting userId: Int64, isVideo: Bool) {
        guard canUpgradeToConference, let call = activeCall else { return }
        let generation = UUID()
        conferenceTransitionGeneration = generation
        conferenceHasReplacedPrivateCall = false
        conferenceAudioWasMoved = false
        isUpgradingToConference = true
        conferenceInvitedUserIds = [userId]

        let coordinator = TelegramGroupCallCoordinator(service: service)
        configureConferenceCallbacks(coordinator)
        coordinator.onPrepared = { [weak self, weak coordinator] prepared in
            guard let self, let coordinator, groupCallCoordinator === coordinator else { return }
            commitConferenceUpgrade(
                coordinator: coordinator,
                prepared: prepared,
                sourceCall: call,
                invitedUserId: userId,
                invitedWithVideo: isVideo,
                generation: generation,
            )
        }
        groupCallCoordinator = coordinator
        log("[GroupCall] creating conference from private callId=\(call.id)")
        coordinator.create(
            isMuted: isMuted,
            privateCallEngine: engine,
            audioSessionActive: isEffectiveAudioSessionActive,
            prioritizeVP8: false,
        )
    }

    func addConferenceParticipant(userId: Int64, isVideo: Bool) {
        if canUpgradeToConference {
            upgradeToConference(inviting: userId, isVideo: isVideo)
            return
        }
        guard canAddConferenceParticipant,
              !excludedConferenceParticipantUserIds.contains(userId),
              let coordinator = groupCallCoordinator
        else { return }

        conferenceInviteTask?.cancel()
        isInvitingConferenceParticipant = true
        conferenceInvitedUserIds.insert(userId)
        conferenceInviteTask = Task { [weak self, weak coordinator] in
            guard let self, let coordinator else { return }
            do {
                _ = try await coordinator.invite(userId: userId, isVideo: isVideo)
                guard groupCallCoordinator === coordinator else { return }
                log("[GroupCall] invited additional userId=\(userId) video=\(isVideo)")
            } catch {
                guard groupCallCoordinator === coordinator else { return }
                conferenceInvitedUserIds.remove(userId)
                log("[GroupCall] couldn't invite additional userId=\(userId): \(error)")
            }
            guard groupCallCoordinator === coordinator else { return }
            isInvitingConferenceParticipant = false
            conferenceInviteTask = nil
        }
    }

    func toggleSpeaker() {
        selectAudioRoute(isSpeakerOn ? .builtIn : .speaker)
    }

    func toggleVideo() {
        if isScreenSharing {
            stopScreenSharing()
            return
        }
        if isLocalVideoEnabled {
            disableLocalVideo()
            return
        }
        guard canToggleVideo, let callId = activeCall?.id else { return }
        isRequestingVideo = true
        Task { [weak self] in
            guard let self else { return }
            let isAuthorized = await Self.requestCameraAccess()
            guard activeCall?.id == callId else {
                isRequestingVideo = false
                return
            }
            isRequestingVideo = false
            guard isAuthorized else {
                showsCameraPermissionAlert = true
                return
            }
            prepareCameraPreview()
        }
    }

    func flipCamera() {
        guard !isScreenSharing,
              let videoCapturer,
              isLocalVideoEnabled || showsCameraPreview
        else { return }
        isUsingFrontCamera.toggle()
        videoCapturer.switchVideoInput(isUsingFrontCamera ? "" : "back")
    }

    func selectCamera(isFront: Bool) {
        guard videoCapturer != nil,
              isLocalVideoEnabled || showsCameraPreview,
              isUsingFrontCamera != isFront
        else { return }
        flipCamera()
    }

    func confirmCameraPreview() {
        guard showsCameraPreview,
              activeCall != nil,
              let videoCapturer
        else {
            cancelCameraPreview()
            return
        }
        showsCameraPreview = false
        isLocalVideoEnabled = true
        localVideoView = cameraPreviewView
        cameraPreviewView = nil
        updateVideoAudioRouting()
        engine.requestVideo(videoCapturer)
        refreshPictureInPictureController()
    }

    func cancelCameraPreview() {
        guard showsCameraPreview || cameraPreviewView != nil else { return }
        videoGeneration = UUID()
        showsCameraPreview = false
        cameraPreviewView = nil
        videoCapturer = nil
        isUsingFrontCamera = true
    }

    func stopScreenSharing() {
        guard isScreenSharing else { return }
        screenShareReceiver?.requestBroadcastStop()
    }

    func selectAudioRoute(_ route: AudioRoute) {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            switch route.kind {
            case .speaker:
                if let builtInMicrophone = audioSession.availableInputs?.first(where: {
                    $0.portType == .builtInMic
                }) {
                    try audioSession.setPreferredInput(builtInMicrophone)
                }
                try audioSession.overrideOutputAudioPort(.speaker)
            case .builtIn:
                try audioSession.overrideOutputAudioPort(.none)
                let builtInMicrophone = audioSession.availableInputs?.first(where: {
                    $0.portType == .builtInMic
                })
                try audioSession.setPreferredInput(builtInMicrophone)
            case .bluetooth, .external, .wired:
                try audioSession.overrideOutputAudioPort(.none)
                guard let input = audioSession.availableInputs?.first(where: {
                    Self.audioRouteId(for: $0) == route.id
                }) else {
                    refreshAudioRoutes()
                    return
                }
                try audioSession.setPreferredInput(input)
            }
            refreshAudioRoutes()
        } catch {
            log("Error selecting call audio route \(route.name): \(error)")
            refreshAudioRoutes()
        }
    }

    func dismissCallRating() {
        pendingCallRating = nil
    }

    func minimizeCallView() {
        guard activeCall != nil else { return }
        let hasVideo = isLocalVideoEnabled || remoteVideoState != .inactive
        if hasVideo, pictureInPictureController?.start() == true {
            // Keep the active source view mounted until AVKit finishes its PiP transition.
            return
        }
        if hasVideo {
            log("[Call] Picture in Picture is not ready; using the in-app minimized call bar")
        }
        isCallViewMinimized = true
    }

    func restoreCallView() {
        guard activeCall != nil else { return }
        isCallViewMinimized = false
        pictureInPictureController?.stop()
    }

    func submitCallRating(
        request: CallRatingRequest,
        rating: Int,
        problems: [TelegramCallRatingProblem],
        comment: String,
    ) async throws {
        guard pendingCallRating?.id == request.id else { return }
        _ = try await service.sendCallRating(
            callId: request.callId,
            comment: comment.isEmpty ? nil : comment,
            problems: problems,
            rating: rating,
        )
        guard pendingCallRating?.id == request.id else { return }
        pendingCallRating = nil
        log("[Call] sent rating=\(rating) for callId=\(request.callId)")
    }

    // MARK: Private

    private enum PendingSystemAction {
        case answer
        case end
    }

    private static let ringingTone = TelegramCallTone.load(resourceName: "voip_ringback", loopCount: 1_000_000)
    private static let connectingTone = TelegramCallTone.load(resourceName: "voip_connecting", loopCount: 1_000_000)
    private static let busyTone = TelegramCallTone.load(resourceName: "voip_busy", loopCount: 3)
    private static let failedTone = TelegramCallTone.load(resourceName: "voip_fail", loopCount: 1)
    private static let endedTone = TelegramCallTone.load(resourceName: "voip_end", loopCount: 1)
    private static let remoteCameraTone = TelegramCallTone.load(
        resourceName: "voip_group_recording_started",
        loopCount: 1,
    )
    private static let terminalToneLifetime: TimeInterval = 2
    private static let endedTonePlaybackDuration: TimeInterval = 1.25

    private let service: any TelegramService
    private let engine = TelegramCallEngine()
    private let cellularNetworkInfo = CTTelephonyNetworkInfo()
    private let networkMonitor = NWPathMonitor()
    private let networkMonitorQueue = DispatchQueue(label: "com.gruiachiscop.BetterTG.call-network")
    private var cancellables = Set<AnyCancellable>()
    private var reportedIncomingCallId: Int?
    private var terminalToneStopTask: Task<Void, Never>?
    private var delayedCallKitEndTask: Task<Void, Never>?
    private var videoAudioRouteTask: Task<Void, Never>?
    private var terminalToneStartedAt: Foundation.Date?
    private var isPreCallAudioDevicePrepared = false
    private var isCallKitAudioSessionActive = false
    private var isEffectiveAudioSessionActive = false
    private var isAudioInterrupted = false
    private var areMediaServicesAvailable = true
    private var ownsProximityMonitoring = false
    private var ownsBatteryMonitoring = false
    private var isEngineRunning = false
    private var engineStartCallId: Int?
    private var engineStartTask: Task<Void, Never>?
    private var isLowBattery = false
    private var networkKind = TelegramCallEngine.NetworkKind.wifi
    private var usesCellularNetwork = false
    private var pendingSystemAction: PendingSystemAction?
    private var isAnswering = false
    private var isEnding = false
    private var lastFinishedCallId: Int?
    private var videoCapturer: OngoingCallThreadLocalContextVideoCapturer?
    private var screenShareCapturer: OngoingCallThreadLocalContextVideoCapturer?
    private var screenShareReceiver: CallScreenShareReceiver?
    private var isRequestingVideo = false
    private var videoGeneration = UUID()
    private var isRequestingRemoteVideoView = false
    private var remoteVideoGeneration = UUID()
    private var pictureInPictureController: CallPictureInPictureController?
    private var conferenceTransitionTask: Task<Void, Never>?
    private var conferenceInviteTask: Task<Void, Never>?
    private var conferenceTransitionGeneration = UUID()
    private var conferenceHasReplacedPrivateCall = false
    private var conferenceAudioWasMoved = false
    private var conferenceInvitedUserIds = Set<Int64>()

    private var shouldRouteVideoToSpeaker: Bool {
        activeCall?.isVideo == true || isLocalVideoEnabled || remoteVideoState != .inactive
    }

    private static func ourProtocol() -> CallProtocol {
        CallProtocol(
            libraryVersions: OngoingCallThreadLocalContextWebrtc.versions(withIncludeReference: false),
            maxLayer: Int(OngoingCallThreadLocalContextWebrtc.maxLayer()),
            minLayer: 65,
            udpP2p: true,
            udpReflector: true,
        )
    }

    /// Telegram negotiates by taking the first remote version also present locally. Choosing the
    /// numerically-highest mutual version can make each peer select a different protocol.
    private static func pickVersion(from theirVersions: [String]) -> String? {
        let ours = Set(OngoingCallThreadLocalContextWebrtc.versions(withIncludeReference: false))
        return theirVersions.first(where: ours.contains)
    }

    private static func networkKind(for accessTechnology: String) -> TelegramCallEngine.NetworkKind {
        switch accessTechnology {
        case CTRadioAccessTechnologyGPRS:
            .cellularGprs
        case CTRadioAccessTechnologyCDMA1x, CTRadioAccessTechnologyEdge:
            .cellularEdge
        case CTRadioAccessTechnologyLTE, CTRadioAccessTechnologyNR, CTRadioAccessTechnologyNRNSA:
            .cellularLte
        case CTRadioAccessTechnologyCDMAEVDORev0,
             CTRadioAccessTechnologyCDMAEVDORevA,
             CTRadioAccessTechnologyCDMAEVDORevB,
             CTRadioAccessTechnologyeHRPD,
             CTRadioAccessTechnologyHSDPA,
             CTRadioAccessTechnologyHSUPA,
             CTRadioAccessTechnologyWCDMA:
            .cellular3g
        default:
            .cellular3g
        }
    }

    private static func describe(networkKind: TelegramCallEngine.NetworkKind) -> String {
        switch networkKind {
        case .wifi: "wifi"
        case .cellularGprs: "gprs"
        case .cellularEdge: "edge"
        case .cellular3g: "3g"
        case .cellularLte: "lte"
        }
    }

    private static func isTerminal(_ state: CallState) -> Bool {
        switch state {
        case .callStateDiscarded, .callStateError: true
        default: false
        }
    }

    private static func endReason(for state: CallState) -> EndReason {
        switch state {
        case .callStateError:
            .failed
        case .callStateDiscarded(let discarded):
            switch discarded.reason {
            case .callDiscardReasonDisconnected:
                .failed
            case .callDiscardReasonMissed:
                .unanswered
            case .callDiscardReasonDeclined,
                 .callDiscardReasonEmpty,
                 .callDiscardReasonHungUp,
                 .callDiscardReasonUpgradeToGroupCall:
                .remoteEnded
            }
        default:
            .remoteEnded
        }
    }

    private static func terminalTone(for state: CallState) -> TelegramCallTone? {
        switch state {
        case .callStateError:
            failedTone
        case .callStateDiscarded(let discarded):
            switch discarded.reason {
            case .callDiscardReasonDeclined:
                busyTone
            case .callDiscardReasonDisconnected:
                failedTone
            case .callDiscardReasonHungUp, .callDiscardReasonMissed:
                endedTone
            case .callDiscardReasonEmpty, .callDiscardReasonUpgradeToGroupCall:
                nil
            }
        default:
            nil
        }
    }

    private static func describe(_ state: CallState) -> String {
        switch state {
        case .callStatePending(let value):
            "pending(isCreated=\(value.isCreated) isReceived=\(value.isReceived))"
        case .callStateExchangingKeys:
            "exchangingKeys"
        case .callStateReady(let value):
            "ready(allowP2p=\(value.allowP2p) servers=\(value.servers.count) protocolVersions=\(value.protocol.libraryVersions.joined(separator: ",")))"
        case .callStateHangingUp:
            "hangingUp"
        case .callStateDiscarded(let value):
            "discarded(reason=\(value.reason) needRating=\(value.needRating) needDebugInformation=\(value.needDebugInformation))"
        case .callStateError(let value):
            "error(code=\(value.error.code) message=\(value.error.message))"
        }
    }

    private static func describe(engineState: TelegramCallEngine.State) -> String {
        switch engineState {
        case .initializing: "initializing"
        case .connected: "connected"
        case .failed: "failed"
        case .reconnecting: "reconnecting"
        case .unknown(let rawValue): "unknown(\(rawValue))"
        }
    }

    private static func audioRouteId(for port: AVAudioSessionPortDescription) -> String {
        "port:\(port.uid)"
    }

    private static func audioRouteKind(for portType: AVAudioSession.Port) -> AudioRoute.Kind {
        switch portType {
        case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE:
            .bluetooth
        case .headphones, .headsetMic, .lineIn:
            .wired
        default:
            .external
        }
    }

    private static func audioRoute(for port: AVAudioSessionPortDescription) -> AudioRoute {
        AudioRoute(
            id: audioRouteId(for: port),
            name: port.portName,
            kind: audioRouteKind(for: port.portType),
        )
    }

    private static func isLowBattery(_ device: UIDevice) -> Bool {
        device.batteryLevel >= 0 && device.batteryLevel < 0.1 && device.batteryState != .charging
    }

    private static func requestCameraAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            true
        case .notDetermined:
            await AVCaptureDevice.requestAccess(for: .video)
        case .denied, .restricted:
            false
        @unknown default:
            false
        }
    }

    private static func connections(from servers: [CallServer]) -> [TelegramCallEngine.Connection] {
        let reflectorIds = servers
            .compactMap { server -> TdInt64? in
                guard case .callServerTypeTelegramReflector = server.type else { return nil }
                return server.id
            }
            .sorted()
        let mapping = Dictionary(uniqueKeysWithValues: reflectorIds.enumerated().map { ($1, UInt8($0 + 1)) })

        return servers.flatMap { server -> [TelegramCallEngine.Connection] in
            switch server.type {
            case .callServerTypeTelegramReflector(let reflector):
                guard let reflectorId = mapping[server.id] else { return [] }
                return [server.ipAddress, server.ipv6Address].filter { !$0.isEmpty }.map { ip in
                    .init(
                        reflectorId: reflectorId,
                        hasStun: false,
                        hasTurn: true,
                        hasTcp: reflector.isTcp,
                        ip: ip,
                        port: Int32(server.port),
                        username: "reflector",
                        password: reflector.peerTag.map { String(format: "%02x", $0) }.joined(),
                    )
                }
            case .callServerTypeWebrtc(let webrtc):
                return [server.ipAddress, server.ipv6Address].filter { !$0.isEmpty }.map { ip in
                    .init(
                        reflectorId: 0,
                        hasStun: webrtc.supportsStun,
                        hasTurn: webrtc.supportsTurn,
                        hasTcp: false,
                        ip: ip,
                        port: Int32(server.port),
                        username: webrtc.username,
                        password: webrtc.password,
                    )
                }
            }
        }
    }

    private nonisolated static func writeTemporaryCallLog(_ callLog: String) -> URL? {
        let url = FileManager.default
            .temporaryDirectory
            .appending(path: "SwiftTG-Call-\(UUID().uuidString).log")
        do {
            try Data(callLog.utf8).write(to: url, options: .atomic)
            return url
        } catch {
            log("Error writing temporary call log: \(error)")
            return nil
        }
    }

    private func handle(call: Call?) {
        guard let call else {
            // `callPublisher` starts with nil. It is not an ended call and must not dismiss a fresh
            // CallKit placeholder or erase an Answer/End action received during a cold launch.
            guard groupCallCoordinator == nil else { return }
            guard activeCall != nil || reportedIncomingCallId != nil || isEngineRunning else { return }
            finishCurrentCall(notifyCallKit: true)
            return
        }

        log("[Call] id=\(call.id) isOutgoing=\(call.isOutgoing) state=\(Self.describe(call.state))")
        if case .callStateDiscarded(let discarded) = call.state,
           case .callDiscardReasonUpgradeToGroupCall(let upgrade) = discarded.reason
        {
            handleConferenceUpgrade(call: call, inviteLink: upgrade.inviteLink)
            return
        }
        if Self.isTerminal(call.state) {
            guard lastFinishedCallId != call.id else {
                log("[Call] ignoring follow-up terminal update for callId=\(call.id)")
                return
            }
            lastFinishedCallId = call.id
            // A terminal update can be TDLib's first update after a VoIP placeholder. Count it as
            // a real call so CallKit is dismissed, but never report it as a fresh incoming call.
            activeCall = call
            let debugInformationCallId: Int? =
                if case .callStateDiscarded(let discarded) = call.state,
                discarded.needDebugInformation {
                    call.id
                } else {
                    nil
                }
            let logCallId: Int? =
                if case .callStateDiscarded(let discarded) = call.state, discarded.needLog {
                    call.id
                } else {
                    nil
                }
            let ratingRequest: CallRatingRequest? =
                if case .callStateDiscarded(let discarded) = call.state, discarded.needRating {
                    CallRatingRequest(callId: call.id, isVideo: call.isVideo)
                } else {
                    nil
                }
            finishCurrentCall(
                notifyCallKit: true,
                endReason: Self.endReason(for: call.state),
                terminalTone: Self.terminalTone(for: call.state),
                debugInformationCallId: debugInformationCallId,
                logCallId: logCallId,
            )
            pendingCallRating = ratingRequest
            return
        }

        if let current = activeCall, current.id != call.id {
            cancelPendingToneCleanup()
            stopEngine()
            reportedIncomingCallId = nil
            encryptionEmojis = []
            isCallViewMinimized = false
        }
        if pendingCallRating?.callId != call.id {
            pendingCallRating = nil
        }
        activeCall = call
        updateVideoAudioRouting()

        if pendingSystemAction == .end {
            pendingSystemAction = nil
            endActiveCall(isDisconnected: false)
            return
        }

        if !call.isOutgoing, reportedIncomingCallId != call.id {
            reportedIncomingCallId = call.id
            onIncomingCall?(call)
        }

        if pendingSystemAction == .answer {
            pendingSystemAction = nil
            answerActiveCall()
        }

        switch call.state {
        case .callStatePending:
            if call.isOutgoing {
                startRingback()
            }
        case .callStateReady(let info):
            encryptionEmojis = info.emojis
            startEngine(call: call, info: info)
        default:
            break
        }
    }

    private func handleConferenceUpgrade(call: Call, inviteLink: String) {
        guard lastFinishedCallId != call.id else {
            log("[Call] ignoring follow-up conference upgrade for callId=\(call.id)")
            return
        }
        lastFinishedCallId = call.id

        // Keep the last non-terminal private-call value as the presentation source while the
        // conference connects. TDLib may publish nil immediately after this discarded update.
        if activeCall?.id != call.id {
            activeCall = call
        }
        conferenceHasReplacedPrivateCall = true
        isUpgradingToConference = false
        guard groupCallCoordinator == nil else {
            log("[GroupCall] private callId=\(call.id) switched to the conference already being prepared")
            moveAudioToConferenceIfReady()
            return
        }

        conferenceAudioWasMoved = false
        cancelPendingToneCleanup()
        stopRingback()
        let coordinator = TelegramGroupCallCoordinator(service: service)
        configureConferenceCallbacks(coordinator)
        groupCallCoordinator = coordinator
        log("[GroupCall] joining conference from private callId=\(call.id)")
        coordinator.join(
            inviteLink: inviteLink,
            isMuted: isMuted,
            privateCallEngine: engine,
            audioSessionActive: isEffectiveAudioSessionActive,
            prioritizeVP8: false,
        )
    }

    private func configureConferenceCallbacks(_ coordinator: TelegramGroupCallCoordinator) {
        coordinator.onConnected = { [weak self, weak coordinator] in
            guard let self, let coordinator, groupCallCoordinator === coordinator else { return }
            moveAudioToConferenceIfReady()
        }
        coordinator.onSignalBarsChanged = { [weak self, weak coordinator] bars in
            guard let self, let coordinator, groupCallCoordinator === coordinator else { return }
            signalBars = bars
        }
        coordinator.onFailed = { [weak self, weak coordinator] in
            guard let self, let coordinator else { return }
            handleConferenceStopped(coordinator, endReason: .failed)
        }
        coordinator.onEnded = { [weak self, weak coordinator] in
            guard let self, let coordinator else { return }
            handleConferenceStopped(coordinator, endReason: .remoteEnded)
        }
    }

    private func commitConferenceUpgrade(
        coordinator: TelegramGroupCallCoordinator,
        prepared: TelegramGroupCallCoordinator.PreparedCall,
        sourceCall: Call,
        invitedUserId: Int64,
        invitedWithVideo: Bool,
        generation: UUID,
    ) {
        guard conferenceTransitionGeneration == generation,
              groupCallCoordinator === coordinator,
              activeCall?.id == sourceCall.id
        else { return }

        conferenceTransitionTask?.cancel()
        conferenceTransitionTask = Task { [weak self, weak coordinator] in
            guard let self, let coordinator else { return }
            let duration = connectedAt.map { max(0, Int(Foundation.Date().timeIntervalSince($0))) } ?? 0
            do {
                _ = try await service.discardCall(
                    callId: sourceCall.id,
                    connectionId: 0,
                    duration: duration,
                    inviteLink: prepared.inviteLink,
                    isDisconnected: false,
                    isVideo: sourceCall.isVideo,
                )
                guard conferenceTransitionGeneration == generation,
                      groupCallCoordinator === coordinator
                else { return }

                conferenceHasReplacedPrivateCall = true
                moveAudioToConferenceIfReady()
                do {
                    _ = try await coordinator.invite(userId: invitedUserId, isVideo: invitedWithVideo)
                    guard conferenceTransitionGeneration == generation,
                          groupCallCoordinator === coordinator
                    else { return }
                    log("[GroupCall] invited userId=\(invitedUserId) video=\(invitedWithVideo)")
                } catch {
                    guard conferenceTransitionGeneration == generation,
                          groupCallCoordinator === coordinator
                    else { return }
                    conferenceInvitedUserIds.remove(invitedUserId)
                    log("[GroupCall] couldn't invite userId=\(invitedUserId): \(error)")
                }
            } catch {
                guard conferenceTransitionGeneration == generation,
                      groupCallCoordinator === coordinator
                else { return }
                log("[GroupCall] couldn't switch private callId=\(sourceCall.id): \(error)")
                resetConferencePreparation(coordinator)
            }
        }
    }

    private func moveAudioToConferenceIfReady() {
        guard conferenceHasReplacedPrivateCall,
              !conferenceAudioWasMoved,
              let coordinator = groupCallCoordinator,
              case .connected = coordinator.state
        else { return }
        conferenceAudioWasMoved = true
        isUpgradingToConference = false
        log("[GroupCall] conference connected; moving incoming audio from the private call")
        coordinator.activateIncomingAudio()
        engine.deactivateIncomingAudio()
        if selectedAudioRoute.kind == .builtIn {
            selectAudioRoute(.speaker)
        }
        CallKitManager.shared.updateCurrentCallAsConference()
        finishPrivateEngineTransition()
    }

    private func handleConferenceStopped(
        _ coordinator: TelegramGroupCallCoordinator,
        endReason: EndReason,
    ) {
        if conferenceHasReplacedPrivateCall {
            finishConference(coordinator, endReason: endReason)
        } else {
            resetConferencePreparation(coordinator)
        }
    }

    private func resetConferencePreparation(_ coordinator: TelegramGroupCallCoordinator) {
        guard groupCallCoordinator === coordinator else { return }
        clearConferenceCallbacks(coordinator)
        if coordinator.groupCall != nil {
            coordinator.leave(endForEveryone: true)
        } else {
            coordinator.cancel()
        }
        conferenceTransitionTask?.cancel()
        conferenceTransitionTask = nil
        conferenceInviteTask?.cancel()
        conferenceInviteTask = nil
        conferenceTransitionGeneration = UUID()
        groupCallCoordinator = nil
        isUpgradingToConference = false
        isInvitingConferenceParticipant = false
        conferenceHasReplacedPrivateCall = false
        conferenceAudioWasMoved = false
        conferenceInvitedUserIds.removeAll()
    }

    private func finishPrivateEngineTransition() {
        engineStartTask?.cancel()
        engineStartTask = nil
        engineStartCallId = nil
        screenShareReceiver?.stop()
        screenShareReceiver = nil
        screenShareCapturer = nil
        isScreenSharing = false
        pictureInPictureController?.stop()
        pictureInPictureController = nil
        pictureInPictureSourceView = nil
        engine.stopForGroupCallTransition()
        isPreCallAudioDevicePrepared = false
        isEngineRunning = false
        videoAudioRouteTask?.cancel()
        videoAudioRouteTask = nil
        stopBatteryMonitoring()
        engineState = .connected
        remoteVideoState = .inactive
        remoteBatteryLevel = .normal
        isRequestingVideo = false
        isLocalVideoEnabled = false
        localVideoView = nil
        cameraPreviewView = nil
        videoCapturer = nil
        videoGeneration = UUID()
        remoteVideoView = nil
        isRequestingRemoteVideoView = false
        remoteVideoGeneration = UUID()
        isUsingFrontCamera = true
        showsCameraPreview = false
        showsCameraPermissionAlert = false
    }

    private func finishConference(
        _ coordinator: TelegramGroupCallCoordinator,
        endReason: EndReason,
    ) {
        guard groupCallCoordinator === coordinator else { return }
        clearConferenceCallbacks(coordinator)
        conferenceTransitionTask?.cancel()
        conferenceTransitionTask = nil
        conferenceInviteTask?.cancel()
        conferenceInviteTask = nil
        conferenceTransitionGeneration = UUID()
        groupCallCoordinator = nil
        isUpgradingToConference = false
        isInvitingConferenceParticipant = false
        conferenceHasReplacedPrivateCall = false
        conferenceAudioWasMoved = false
        conferenceInvitedUserIds.removeAll()
        finishCurrentCall(notifyCallKit: true, endReason: endReason)
    }

    private func clearConferenceCallbacks(_ coordinator: TelegramGroupCallCoordinator) {
        coordinator.onPrepared = nil
        coordinator.onConnected = nil
        coordinator.onSignalBarsChanged = nil
        coordinator.onFailed = nil
        coordinator.onEnded = nil
    }

    private func answerActiveCall() {
        guard let call = activeCall else {
            log("[Call] answer() called with no activeCall")
            return
        }
        guard !isAnswering else { return }
        isAnswering = true
        log("[Call] accepting callId=\(call.id)")
        Task { [weak self] in
            guard let self else { return }
            defer {
                if activeCall?.id == call.id {
                    isAnswering = false
                }
            }
            if call.isVideo {
                let cameraGranted = await Self.requestCameraAccess()
                guard activeCall?.id == call.id else {
                    log("[Call] video answer superseded while waiting for camera permission")
                    return
                }
                guard cameraGranted else {
                    log("[Call] camera permission denied; incoming video call rejected")
                    showsCameraPermissionAlert = true
                    endActiveCall(isDisconnected: false)
                    return
                }
            }
            do {
                _ = try await service.acceptCall(callId: call.id, protocol: Self.ourProtocol())
                if activeCall?.id == call.id {
                    log("[Call] acceptCall RPC succeeded for callId=\(call.id)")
                }
            } catch {
                log("Error accepting call: \(error)")
                guard activeCall?.id == call.id else {
                    log("[Call] ignoring stale acceptCall failure for callId=\(call.id)")
                    return
                }
                endActiveCall(isDisconnected: true)
            }
        }
    }

    private func endActiveCall(isDisconnected: Bool, completion: ((Bool) -> Void)? = nil) {
        guard let call = activeCall else {
            completion?(false)
            return
        }
        guard !isEnding else {
            completion?(false)
            return
        }
        isEnding = true
        let endedToneStartedAt = isDisconnected ? nil : playTerminalToneIfNeeded(Self.endedTone)
        let duration = connectedAt.map { max(0, Int(Foundation.Date().timeIntervalSince($0))) } ?? 0
        Task { [weak self] in
            guard let self else {
                completion?(false)
                return
            }
            defer {
                if activeCall?.id == call.id {
                    isEnding = false
                }
            }
            do {
                _ = try await service.discardCall(
                    callId: call.id,
                    connectionId: 0,
                    duration: duration,
                    inviteLink: nil,
                    isDisconnected: isDisconnected,
                    isVideo: call.isVideo,
                )
                if let endedToneStartedAt, completion != nil {
                    let elapsed = Foundation.Date().timeIntervalSince(endedToneStartedAt)
                    let remaining = Self.endedTonePlaybackDuration - elapsed
                    if remaining > 0 {
                        try? await Task.sleep(for: .seconds(remaining))
                    }
                }
                completion?(true)
            } catch {
                log("Error discarding call: \(error)")
                if let completion {
                    completion(false)
                } else if activeCall?.id == call.id {
                    finishCurrentCall(notifyCallKit: true)
                } else {
                    log("[Call] ignoring stale discardCall failure for callId=\(call.id)")
                }
            }
        }
    }

    private func startRingback() {
        guard !isPreCallAudioDevicePrepared, !isEngineRunning, let ringingTone = Self.ringingTone else { return }
        terminalToneStopTask?.cancel()
        terminalToneStopTask = nil
        terminalToneStartedAt = nil
        isPreCallAudioDevicePrepared = true
        engine.prepareAudioDevice(tone: ringingTone, audioSessionActive: isEffectiveAudioSessionActive)
    }

    @discardableResult private func playTerminalToneIfNeeded(_ tone: TelegramCallTone?) -> Foundation.Date? {
        guard let tone else { return nil }
        if let terminalToneStartedAt {
            return terminalToneStartedAt
        }

        let startedAt = Foundation.Date()
        terminalToneStartedAt = startedAt
        isPreCallAudioDevicePrepared = true
        engine.prepareAudioDevice(tone: tone, audioSessionActive: isEffectiveAudioSessionActive)

        terminalToneStopTask?.cancel()
        terminalToneStopTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(Self.terminalToneLifetime))
            } catch {
                return
            }
            guard let self, terminalToneStartedAt == startedAt else { return }
            terminalToneStartedAt = nil
            terminalToneStopTask = nil
        }
        return startedAt
    }

    private func applyAudioSessionActive(_ active: Bool) {
        isCallKitAudioSessionActive = active
        applyEffectiveAudioSessionState()
        refreshAudioRoutes()
        routeVideoToSpeakerIfNeeded()
    }

    private func applyEffectiveAudioSessionState() {
        let active = isCallKitAudioSessionActive && !isAudioInterrupted && areMediaServicesAvailable
        guard active != isEffectiveAudioSessionActive else { return }
        isEffectiveAudioSessionActive = active
        log(
            "[Call] audio session effective=\(active) CallKit=\(isCallKitAudioSessionActive) interrupted=\(isAudioInterrupted) mediaServices=\(areMediaServicesAvailable)",
        )
        engine.setAudioSessionActive(active)
        groupCallCoordinator?.setAudioSessionActive(active)
    }

    private func applyNetworkKind(_ kind: TelegramCallEngine.NetworkKind) {
        guard networkKind != kind else { return }
        networkKind = kind
        log("[Call] network kind=\(Self.describe(networkKind: kind))")
        engine.setNetworkKind(kind)
    }

    private func refreshNetworkKind() {
        guard usesCellularNetwork else {
            applyNetworkKind(.wifi)
            return
        }
        let accessTechnology = cellularNetworkInfo.serviceCurrentRadioAccessTechnology?.values.first ?? ""
        applyNetworkKind(Self.networkKind(for: accessTechnology))
    }

    private func stopRingback() {
        guard terminalToneStartedAt == nil else { return }
        engine.setTone(nil)
    }

    private func cancelPendingToneCleanup() {
        terminalToneStopTask?.cancel()
        terminalToneStopTask = nil
        terminalToneStartedAt = nil
    }

    private func handleSignaling(_ data: UpdateNewCallSignalingData) {
        guard data.callId == activeCall?.id else { return }
        engine.addSignaling(data.data)
    }

    private func startEngine(call: Call, info: CallStateReady) {
        guard !isEngineRunning, engineStartCallId == nil else { return }
        guard let version = Self.pickVersion(from: info.protocol.libraryVersions) else {
            log("No mutually supported call protocol version")
            stopRingback()
            endActiveCall(isDisconnected: true)
            return
        }

        let callId = call.id
        engineStartCallId = callId
        engineStartTask = Task { [weak self] in
            guard let self else { return }
            async let configuredProxy = configuredCallProxy()
            async let configuredStunMarking = configuredStunMarkingEnabled()
            let (proxy, enableStunMarking) = await (configuredProxy, configuredStunMarking)
            defer {
                if engineStartCallId == callId {
                    engineStartCallId = nil
                    engineStartTask = nil
                }
            }
            guard !Task.isCancelled, activeCall?.id == callId, !isEngineRunning else { return }
            startEngine(
                call: call,
                info: info,
                version: version,
                proxy: proxy,
                enableStunMarking: enableStunMarking,
            )
        }
    }

    private func startEngine(
        call: Call,
        info: CallStateReady,
        version: String,
        proxy: TelegramCallEngine.ProxyServer?,
        enableStunMarking: Bool,
    ) {
        isEngineRunning = true
        startBatteryMonitoring()
        let callId = call.id
        let dataSaving: TelegramCallEngine.DataSaving =
            switch TelegramCallSettings.dataSaving {
            case .never: .never
            case .cellular: .cellular
            case .always: .always
            }
        engine.start(
            configuration: .init(
                version: version,
                customParameters: info.customParameters.isEmpty ? nil : info.customParameters,
                encryptionKey: info.encryptionKey,
                isOutgoing: call.isOutgoing,
                connections: Self.connections(from: info.servers),
                maxLayer: Int32(info.protocol.maxLayer),
                allowP2P: info.allowP2p,
                // Telegram-iOS keeps VoIP-over-TCP behind its disabled-by-default experimental
                // switch. SwiftTG has no equivalent switch, so use the same production default.
                allowTCP: false,
                enableStunMarking: enableStunMarking,
                dataSaving: dataSaving,
                proxy: proxy,
            ),
            muted: isMuted,
            lowBattery: isLowBattery,
            audioSessionActive: isEffectiveAudioSessionActive,
            networkKind: networkKind,
            sendSignaling: { [weak self] data in
                Task { @MainActor [weak self] in
                    guard let self, activeCall?.id == callId else { return }
                    do {
                        _ = try await service.sendCallSignalingData(callId: callId, data: data)
                    } catch {
                        log("Error sending call signaling: \(error)")
                    }
                }
            },
            stateChanged: { [weak self] state, remoteVideoState, remoteAudioState, remoteBatteryLevel in
                Task { @MainActor [weak self] in
                    self?.handleEngineState(
                        state,
                        remoteVideoState: remoteVideoState,
                        remoteAudioState: remoteAudioState,
                        remoteBatteryLevel: remoteBatteryLevel,
                        callId: callId,
                    )
                }
            },
            signalBarsChanged: { [weak self] signalBars in
                Task { @MainActor [weak self] in
                    self?.handleSignalBars(signalBars, callId: callId)
                }
            },
        )
        startScreenShareReceiver()
        // Telegram starts both sides of an explicitly-video call with their camera enabled. For
        // incoming calls, `answerActiveCall()` has already obtained permission before accepting;
        // outgoing calls are authorized before CallKit creates the call.
        if call.isVideo, AVCaptureDevice.authorizationStatus(for: .video) == .authorized {
            enableLocalVideo()
        }
        engine.setTone(Self.connectingTone)
    }

    private func handleEngineState(
        _ state: TelegramCallEngine.State,
        remoteVideoState: TelegramCallEngine.RemoteVideoState,
        remoteAudioState: TelegramCallEngine.RemoteAudioState,
        remoteBatteryLevel: TelegramCallEngine.RemoteBatteryLevel,
        callId: Int,
    ) {
        guard isEngineRunning, activeCall?.id == callId else { return }
        log("[Call] engine state=\(Self.describe(engineState: state))")
        engineState = state
        switch state {
        case .initializing, .reconnecting:
            engine.setTone(Self.connectingTone)
        case .connected, .failed, .unknown:
            engine.setTone(nil)
        }
        handleRemoteVideoState(remoteVideoState, callId: callId)
        if self.remoteAudioState != remoteAudioState {
            self.remoteAudioState = remoteAudioState
            log("[Call] remote audio=\(remoteAudioState)")
        }
        if self.remoteBatteryLevel != remoteBatteryLevel {
            self.remoteBatteryLevel = remoteBatteryLevel
            log("[Call] remote battery=\(remoteBatteryLevel)")
        }
        if connectedAt == nil, state == .connected {
            connectedAt = Foundation.Date()
            onCallConnected?()
        } else if state == .failed {
            endActiveCall(isDisconnected: true)
        }
    }

    private func handleRemoteVideoState(_ state: TelegramCallEngine.RemoteVideoState, callId: Int) {
        let previousState = remoteVideoState
        if remoteVideoState != state {
            remoteVideoState = state
            log("[Call] remote video=\(state)")
        }
        if previousState == .inactive,
           state != .inactive,
           selectedAudioRoute.kind == .builtIn
        {
            // Telegram plays this cue only when an audio call is still using the receiver. Video
            // routing may promote that receiver to speaker immediately after this state change.
            engine.setTone(Self.remoteCameraTone)
        }
        updateVideoAudioRouting()
        refreshPictureInPictureController()

        switch state {
        case .active, .paused:
            guard remoteVideoView == nil, !isRequestingRemoteVideoView else { return }
            let generation = UUID()
            remoteVideoGeneration = generation
            isRequestingRemoteVideoView = true
            engine.makeIncomingVideoView { [weak self] videoView in
                guard let self else { return }
                isRequestingRemoteVideoView = false
                guard remoteVideoGeneration == generation,
                      activeCall?.id == callId,
                      remoteVideoState != .inactive
                else { return }
                remoteVideoView = videoView
            }
        case .inactive:
            remoteVideoGeneration = UUID()
            isRequestingRemoteVideoView = false
            remoteVideoView = nil
        }
    }

    private func handleSignalBars(_ bars: Int32, callId: Int) {
        guard isEngineRunning, activeCall?.id == callId else { return }
        let updatedBars = min(4, max(0, Int(bars)))
        guard signalBars != updatedBars else { return }
        signalBars = updatedBars
        log("[Call] signal bars=\(updatedBars)")
    }

    private func handleAudioRouteChange(_ notification: Foundation.Notification) {
        let reason = (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? NSNumber)?.uintValue
        refreshAudioRoutes()
        routeVideoToSpeakerIfNeeded()
        log(
            "[Call] audio route changed reason=\(reason.map(String.init) ?? "unknown") selected=\(selectedAudioRoute.name)",
        )
    }

    private func configuredCallProxy() async -> TelegramCallEngine.ProxyServer? {
        guard TelegramCallSettings.usesProxyForCalls else { return nil }
        do {
            let proxies = try await service.getProxies().proxies
            guard let proxy = proxies.first(where: \.isEnabled) else { return nil }
            guard case .proxyTypeSocks5(let credentials) = proxy.proxy.type else { return nil }
            log("[Call] using configured SOCKS5 proxy")
            return TelegramCallEngine.ProxyServer(
                host: proxy.proxy.server,
                port: Int32(clamping: proxy.proxy.port),
                username: credentials.username,
                password: credentials.password,
            )
        } catch {
            log("[Call] couldn't load proxy configuration: \(error)")
            return nil
        }
    }

    private func configuredStunMarkingEnabled() async -> Bool {
        do {
            let configuration = try await service.getApplicationConfig()
            guard case .jsonValueObject(let object) = configuration,
                  let member = object.members.first(where: { $0.key == "voip_enable_stun_marking" }),
                  case .jsonValueBoolean(let value) = member.value
            else { return true }
            return value.value
        } catch {
            log("[Call] couldn't load STUN marking configuration: \(error)")
            return true
        }
    }

    private func refreshAudioRoutes() {
        let audioSession = AVAudioSession.sharedInstance()
        var routes: [AudioRoute] = [.builtIn, .speaker]
        for input in audioSession.availableInputs ?? [] where input.portType != .builtInMic {
            let route = Self.audioRoute(for: input)
            if !routes.contains(where: { $0.id == route.id }) {
                routes.append(route)
            }
        }

        let currentRoute = audioSession.currentRoute
        let selected: AudioRoute =
            if currentRoute.outputs.contains(where: { $0.portType == .builtInSpeaker }) {
                .speaker
            } else if currentRoute.outputs.contains(where: { $0.portType == .builtInReceiver }) {
                .builtIn
            } else if let input = currentRoute.inputs.first(where: { $0.portType != .builtInMic }) {
                Self.audioRoute(for: input)
            } else if let output = currentRoute.outputs.first(where: {
                $0.portType != .builtInReceiver && $0.portType != .builtInSpeaker
            }) {
                Self.audioRoute(for: output)
            } else {
                .builtIn
            }

        if !routes.contains(where: { $0.id == selected.id }) {
            routes.append(selected)
        }
        availableAudioRoutes = routes
        selectedAudioRoute = selected
        isSpeakerOn = selected.kind == .speaker
        updateProximityMonitoring()
    }

    /// Keep the display protected from accidental touches only while the receiver is the actual
    /// output during an audio-only call. Video must keep the display awake even if CallKit enables
    /// proximity after its audio handoff, so video disables it authoritatively. For audio-only
    /// calls the ownership flag still avoids disabling monitoring owned by another component.
    private func updateProximityMonitoring() {
        let device = UIDevice.current
        if activeCall != nil, shouldRouteVideoToSpeaker {
            if device.isProximityMonitoringEnabled {
                device.isProximityMonitoringEnabled = false
                log("[Call] proximity monitoring force-disabled for video")
            }
            ownsProximityMonitoring = false
            return
        }

        let shouldMonitor = activeCall != nil
            && selectedAudioRoute.kind == .builtIn
        if shouldMonitor, !ownsProximityMonitoring {
            device.isProximityMonitoringEnabled = true
            ownsProximityMonitoring = device.isProximityMonitoringEnabled
            log("[Call] proximity monitoring enabled=\(ownsProximityMonitoring)")
        } else if !shouldMonitor, ownsProximityMonitoring {
            device.isProximityMonitoringEnabled = false
            ownsProximityMonitoring = false
            log("[Call] proximity monitoring disabled")
        }
    }

    /// Telegram-iOS defaults video calls to speaker and repeatedly restores it because CallKit can
    /// briefly reset the route during activation. Wired, Bluetooth, and external routes are never
    /// replaced; only the built-in receiver is promoted to speaker.
    private func updateVideoAudioRouting() {
        guard activeCall != nil, shouldRouteVideoToSpeaker else {
            videoAudioRouteTask?.cancel()
            videoAudioRouteTask = nil
            updateProximityMonitoring()
            return
        }

        routeVideoToSpeakerIfNeeded()
        updateProximityMonitoring()
        guard videoAudioRouteTask == nil else { return }

        videoAudioRouteTask = Task { [weak self] in
            while let self, !Task.isCancelled, activeCall != nil, shouldRouteVideoToSpeaker {
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                routeVideoToSpeakerIfNeeded()
                updateProximityMonitoring()
            }
        }
    }

    private func routeVideoToSpeakerIfNeeded() {
        guard activeCall != nil,
              shouldRouteVideoToSpeaker,
              isEffectiveAudioSessionActive,
              selectedAudioRoute.kind == .builtIn
        else { return }
        log("[Call] routing video call from receiver to speaker")
        selectAudioRoute(.speaker)
    }

    private func handleAudioInterruption(_ notification: Foundation.Notification) {
        guard
            let rawType = (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? NSNumber)?.uintValue,
            let type = AVAudioSession.InterruptionType(rawValue: rawType)
        else { return }

        switch type {
        case .began:
            isAudioInterrupted = true
            log("[Call] audio interruption began")
        case .ended:
            isAudioInterrupted = false
            let rawOptions = (notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? NSNumber)?.uintValue ?? 0
            let shouldResume = AVAudioSession.InterruptionOptions(rawValue: rawOptions).contains(.shouldResume)
            log("[Call] audio interruption ended shouldResume=\(shouldResume)")
        @unknown default:
            return
        }
        applyEffectiveAudioSessionState()
        refreshAudioRoutes()
    }

    private func handleMediaServicesLost() {
        areMediaServicesAvailable = false
        log("[Call] audio media services lost")
        applyEffectiveAudioSessionState()
    }

    private func handleMediaServicesReset() {
        areMediaServicesAvailable = true
        log("[Call] audio media services reset")
        if activeCall != nil {
            Self.prepareAudioSession()
        }
        applyEffectiveAudioSessionState()
        refreshAudioRoutes()
    }

    private func startBatteryMonitoring() {
        let device = UIDevice.current
        if !device.isBatteryMonitoringEnabled {
            device.isBatteryMonitoringEnabled = true
            ownsBatteryMonitoring = device.isBatteryMonitoringEnabled
        }
        refreshLowBatteryState()
        log("[Call] battery monitoring started low=\(isLowBattery)")
    }

    private func refreshLowBatteryState() {
        guard isEngineRunning else { return }
        let lowBattery = Self.isLowBattery(UIDevice.current)
        guard lowBattery != isLowBattery else { return }
        isLowBattery = lowBattery
        log("[Call] low battery=\(lowBattery)")
        engine.setLowBattery(lowBattery)
    }

    private func stopBatteryMonitoring() {
        if ownsBatteryMonitoring {
            UIDevice.current.isBatteryMonitoringEnabled = false
            ownsBatteryMonitoring = false
        }
        isLowBattery = false
    }

    private func enableLocalVideo() {
        guard !isLocalVideoEnabled else { return }
        let capturer = OngoingCallThreadLocalContextVideoCapturer(deviceId: "", keepLandscape: false)
        let generation = UUID()
        videoGeneration = generation
        videoCapturer = capturer
        isUsingFrontCamera = true
        isLocalVideoEnabled = true
        updateVideoAudioRouting()
        capturer.makeOutgoingVideoView(false) { [weak self] videoView, _ in
            MainActor.assumeIsolated {
                guard let self, self.videoGeneration == generation, self.isLocalVideoEnabled else { return }
                self.localVideoView = videoView
            }
        }
        engine.requestVideo(capturer)
        refreshPictureInPictureController()
    }

    private func startScreenShareReceiver() {
        guard screenShareReceiver == nil else { return }
        let receiver = CallScreenShareReceiver(
            frameReceived: { [weak self] frame in
                guard let self, isScreenSharing, let screenShareCapturer else { return }
                screenShareCapturer.submitSampleBuffer(
                    frame.sampleBuffer,
                    rotation: frame.rotation,
                    completion: {},
                )
            },
            audioReceived: { [weak self] data in
                guard let self, isScreenSharing else { return }
                engine.addExternalAudioData(data)
            },
            activeChanged: { [weak self] active in
                self?.setScreenSharingActive(active)
            },
        )
        screenShareReceiver = receiver
        receiver.start()
    }

    private func setScreenSharingActive(_ active: Bool) {
        guard active != isScreenSharing else { return }
        if active {
            cancelCameraPreview()
            if isLocalVideoEnabled {
                disableLocalVideo()
            }
            let capturer = OngoingCallThreadLocalContextVideoCapturer.withExternalSampleBufferProvider()
            let generation = UUID()
            videoGeneration = generation
            screenShareCapturer = capturer
            isScreenSharing = true
            isLocalVideoEnabled = true
            isUsingFrontCamera = true
            updateVideoAudioRouting()
            capturer.makeOutgoingVideoView(false) { [weak self] videoView, _ in
                MainActor.assumeIsolated {
                    guard let self,
                          self.videoGeneration == generation,
                          self.isScreenSharing
                    else { return }
                    self.localVideoView = videoView
                }
            }
            engine.requestVideo(capturer)
            refreshPictureInPictureController()
            log("[Call] screen sharing started")
        } else {
            engine.disableVideo()
            videoGeneration = UUID()
            screenShareCapturer = nil
            isScreenSharing = false
            isLocalVideoEnabled = false
            localVideoView = nil
            updateVideoAudioRouting()
            refreshPictureInPictureController()
            log("[Call] screen sharing stopped")
        }
    }

    private func prepareCameraPreview() {
        guard !isLocalVideoEnabled, !showsCameraPreview else { return }
        let capturer = OngoingCallThreadLocalContextVideoCapturer(deviceId: "", keepLandscape: false)
        let generation = UUID()
        videoGeneration = generation
        videoCapturer = capturer
        isUsingFrontCamera = true
        showsCameraPreview = true
        capturer.makeOutgoingVideoView(false) { [weak self] videoView, _ in
            MainActor.assumeIsolated {
                guard let self,
                      self.videoGeneration == generation,
                      self.showsCameraPreview
                else { return }
                self.cameraPreviewView = videoView
            }
        }
    }

    private func disableLocalVideo() {
        guard isLocalVideoEnabled else { return }
        engine.disableVideo()
        videoGeneration = UUID()
        isLocalVideoEnabled = false
        localVideoView = nil
        videoCapturer = nil
        videoGeneration = UUID()
        isUsingFrontCamera = true
        isScreenSharing = false
        screenShareCapturer = nil
        updateVideoAudioRouting()
        refreshPictureInPictureController()
    }

    private func refreshPictureInPictureController() {
        let isIncoming: Bool
        if remoteVideoState != .inactive {
            isIncoming = true
        } else if isLocalVideoEnabled {
            isIncoming = false
        } else {
            pictureInPictureController?.stop()
            pictureInPictureController = nil
            pictureInPictureSourceView = nil
            return
        }

        if pictureInPictureController?.isIncoming == isIncoming {
            return
        }

        pictureInPictureController?.stop()
        let videoView = TelegramCallSampleBufferVideoView(engine: engine, isIncoming: isIncoming)
        guard let controller = CallPictureInPictureController(
            videoView: videoView,
            isIncoming: isIncoming,
        ) else {
            pictureInPictureController = nil
            pictureInPictureSourceView = nil
            return
        }
        controller.restoreCallInterface = { [weak self] completion in
            guard let self, activeCall != nil else {
                completion(false)
                return
            }
            restoreCallView()
            completion(true)
        }
        controller.didStartPictureInPicture = { [weak self] in
            guard let self, activeCall != nil else { return }
            isCallViewMinimized = true
        }
        controller.didFailToStartPictureInPicture = { [weak self] in
            guard let self, activeCall != nil else { return }
            isCallViewMinimized = true
        }
        pictureInPictureController = controller
        pictureInPictureSourceView = controller.sourceView
    }

    private func stopEngine(
        debugInformationCallId: Int? = nil,
        logCallId: Int? = nil,
        finalTone: TelegramCallTone? = nil,
    ) {
        engineStartTask?.cancel()
        engineStartTask = nil
        engineStartCallId = nil
        screenShareReceiver?.stop()
        screenShareReceiver = nil
        screenShareCapturer = nil
        isScreenSharing = false
        pictureInPictureController?.stop()
        pictureInPictureController = nil
        pictureInPictureSourceView = nil
        let retentionDuration = finalTone == nil ? 0 : Self.terminalToneLifetime
        if debugInformationCallId != nil || logCallId != nil {
            let service = service
            engine.stop(finalTone: finalTone, retainAudioDeviceFor: retentionDuration) { result in
                guard let result else { return }
                let logURL: URL? =
                    if logCallId != nil, let callLog = result.callLog {
                        Self.writeTemporaryCallLog(callLog)
                    } else {
                        nil
                    }
                Task {
                    if let debugInformationCallId, let debugInformation = result.debugInformation {
                        do {
                            _ = try await service.sendCallDebugInformation(
                                callId: debugInformationCallId,
                                debugInformation: debugInformation,
                            )
                            log("[Call] sent requested debug information for callId=\(debugInformationCallId)")
                        } catch {
                            log("Error sending call debug information: \(error)")
                        }
                    }
                    if let logCallId, let logURL {
                        defer { try? FileManager.default.removeItem(at: logURL) }
                        do {
                            _ = try await service.sendCallLog(callId: logCallId, path: logURL.path)
                            log("[Call] sent requested call log for callId=\(logCallId)")
                        } catch {
                            log("Error sending call log: \(error)")
                        }
                    }
                }
            }
        } else {
            engine.stop(finalTone: finalTone, retainAudioDeviceFor: retentionDuration)
        }
        isPreCallAudioDevicePrepared = false
        isEngineRunning = false
        videoAudioRouteTask?.cancel()
        videoAudioRouteTask = nil
        stopBatteryMonitoring()
        engineState = nil
        remoteAudioState = .active
        remoteVideoState = .inactive
        remoteBatteryLevel = .normal
        signalBars = nil
        isMuted = false
        connectedAt = nil
        isRequestingVideo = false
        isLocalVideoEnabled = false
        localVideoView = nil
        cameraPreviewView = nil
        videoCapturer = nil
        videoGeneration = UUID()
        remoteVideoView = nil
        isRequestingRemoteVideoView = false
        remoteVideoGeneration = UUID()
        isUsingFrontCamera = true
        showsCameraPreview = false
        showsCameraPermissionAlert = false
        if isSpeakerOn {
            do {
                try AVAudioSession.sharedInstance().overrideOutputAudioPort(.none)
            } catch {
                log("Error restoring call audio route: \(error)")
            }
        }
        refreshAudioRoutes()
    }

    private func finishCurrentCall(
        notifyCallKit: Bool,
        endReason: EndReason = .remoteEnded,
        terminalTone: TelegramCallTone? = nil,
        debugInformationCallId: Int? = nil,
        logCallId: Int? = nil,
    ) {
        if let coordinator = groupCallCoordinator {
            resetConferencePreparation(coordinator)
        }
        let hadCall = activeCall != nil || reportedIncomingCallId != nil || isEngineRunning
        let wasOutgoing = activeCall?.isOutgoing == true
        let selectedTerminalTone = terminalToneStartedAt == nil ? terminalTone : Self.endedTone
        let didStartTerminalTone = playTerminalToneIfNeeded(selectedTerminalTone) != nil
        activeCall = nil
        reportedIncomingCallId = nil
        pendingSystemAction = nil
        isAnswering = false
        isEnding = false
        encryptionEmojis = []
        isCallViewMinimized = false
        if !didStartTerminalTone {
            stopRingback()
        }
        stopEngine(
            debugInformationCallId: debugInformationCallId,
            logCallId: logCallId,
            finalTone: didStartTerminalTone ? selectedTerminalTone : nil,
        )
        if notifyCallKit, hadCall {
            if didStartTerminalTone, wasOutgoing {
                delayedCallKitEndTask?.cancel()
                delayedCallKitEndTask = Task { [weak self] in
                    do {
                        try await Task.sleep(for: .seconds(Self.terminalToneLifetime))
                    } catch {
                        return
                    }
                    guard let self else { return }
                    onCallEnded?(endReason)
                    delayedCallKitEndTask = nil
                }
            } else {
                onCallEnded?(endReason)
            }
        }
    }
}
