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

// MARK: - InputGroupCall + @retroactive @unchecked Sendable

extension InputGroupCall: @retroactive @unchecked Sendable {}

// MARK: - TelegramCallSession

/// Bridges TDLib's call state/signaling to the vendored tgcalls engine. TelegramCallEngine owns the
/// strict tgcalls queue confinement.
@MainActor
@Observable final class TelegramCallSession {
    // MARK: Lifecycle

    init(service: any TelegramService) {
        self.service = service
        self.conferenceAccessibilityAnnouncer = ConferenceAccessibilityAnnouncer(service: service)
        service.callPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] call in self?.handle(call: call) }
            .store(in: &cancellables)
        service.callSignalingDataPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] data in self?.handleSignaling(data) }
            .store(in: &cancellables)
        service.updatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] update in self?.handleConferenceInvitationUpdate(update) }
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

    struct IncomingConferenceInvitation: Equatable, Sendable {
        let chatId: Int64
        let messageId: Int64
        let uniqueId: Int64
        let inviterUserId: Int64?
        let displayTitle: String?
        let isVideo: Bool
    }

    static let shared = TelegramCallSession(service: TDLib.shared.service)

    private(set) var activeCall: Call?
    private(set) var incomingConferenceInvitation: IncomingConferenceInvitation?

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
    private(set) var conferenceParticipantActionId: String?
    private(set) var isLocalVideoEnabled = false
    private(set) var localVideoView: UIView?
    private(set) var cameraPreviewView: UIView?
    private(set) var remoteVideoView: UIView?
    private(set) var pictureInPictureSourceView: UIView?
    private(set) var isUsingFrontCamera = true
    private(set) var showsCameraPreview = false
    private(set) var isScreenSharing = false
    var showsCameraPermissionAlert = false
    var showsConferenceInvitationError = false
    private(set) var conferenceInvitationErrorMessage = "SwiftTG couldn't invite this participant."
    var pendingCallRating: CallRatingRequest?
    private(set) var callRatingSuccessToken: UUID?

    var onIncomingCall: ((Call) -> Void)?
    var onIncomingConferenceInvitation: ((IncomingConferenceInvitation) -> Void)?
    var onCallConnected: (() -> Void)?
    var onCallEnded: ((EndReason) -> Void)?

    /// The native CallKit UI remains the sole incoming-answer surface while the call is pending.
    var shouldShowCallView: Bool {
        if groupCallCoordinator != nil {
            return !isCallViewMinimized
        }
        guard let activeCall else { return false }
        if !activeCall.isOutgoing, case .callStatePending = activeCall.state {
            return false
        }
        return !isCallViewMinimized
    }

    var shouldShowMinimizedCallBar: Bool { hasActiveCallSurface && isCallViewMinimized }

    var isConferenceCall: Bool { groupCallCoordinator != nil }

    var isStandaloneConferenceCall: Bool { groupCallCoordinator != nil && activeCall == nil }

    var showsConferenceCallUI: Bool {
        conferenceHasReplacedPrivateCall && (conferenceAudioWasMoved || isStandaloneConferenceCall)
    }

    var canEndConferenceForEveryone: Bool {
        showsConferenceCallUI && groupCallCoordinator?.groupCall?.isOwned == true
    }

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

    var conferenceMessages: [ConferenceMessagePresentation] {
        guard let groupCallCoordinator else { return [] }
        return groupCallCoordinator.messages
            .values
            .sorted { lhs, rhs in
                if lhs.date == rhs.date {
                    return lhs.messageId < rhs.messageId
                }
                return lhs.date < rhs.date
            }
            .map { message in
                let userId: Int64?
                let chatId: Int64?
                switch message.senderId {
                case .messageSenderUser(let sender):
                    userId = sender.userId
                    chatId = nil
                case .messageSenderChat(let sender):
                    userId = nil
                    chatId = sender.chatId
                }
                return ConferenceMessagePresentation(
                    id: message.messageId,
                    userId: userId,
                    chatId: chatId,
                    formattedText: message.text,
                    date: Date(timeIntervalSince1970: TimeInterval(message.date)),
                )
            }
    }

    var conferenceMessageCharacterLimit: Int {
        groupCallCoordinator?.messageCharacterLimit ?? 128
    }

    var areConferenceMessagesAvailable: Bool {
        groupCallCoordinator?.groupCall?.areMessagesAllowed == true
    }

    var canSendConferenceMessages: Bool {
        guard let groupCall = groupCallCoordinator?.groupCall else { return false }
        return groupCall.areMessagesAllowed && groupCall.canSendMessages
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

    var conferenceParticipantPresentations: [ConferenceParticipantPresentation] {
        let speakingParticipantIds = conferenceSpeakingParticipantIds
        let joined = conferenceParticipants.map { participant in
            let userId: Int64?
            let chatId: Int64?
            let id: String
            switch participant.participantId {
            case .messageSenderUser(let sender):
                userId = sender.userId
                chatId = nil
                id = "user-\(sender.userId)"
            case .messageSenderChat(let sender):
                userId = nil
                chatId = sender.chatId
                id = "chat-\(sender.chatId)"
            }

            let participantIsSpeaking = speakingParticipantIds.contains(participant.participantId)
            let participantIsMuted = participant.isCurrentUser
                ? isMuted
                : participant.isMutedForAllUsers || participant.isMutedForCurrentUser
            let subtitle: String =
                if participant.isCurrentUser {
                    "You"
                } else if participantIsSpeaking {
                    "Speaking"
                } else if participant.isHandRaised {
                    "Hand raised"
                } else if participantIsMuted {
                    "Muted"
                } else {
                    participant.bio.isEmpty ? "Listening" : participant.bio
                }

            return ConferenceParticipantPresentation(
                id: id,
                userId: userId,
                chatId: chatId,
                title: nil,
                subtitle: subtitle,
                isSpeaking: participantIsSpeaking,
                isMuted: participantIsMuted,
                isHandRaised: participant.isHandRaised,
                isInvited: false,
                muteAction: conferenceMuteAction(for: participant),
                canRemove: groupCallCoordinator?.groupCall?.isOwned == true
                    && !participant.isCurrentUser
                    && userId != nil,
            )
        }
        let invited = pendingConferenceInvitedUserIds.map { userId in
            ConferenceParticipantPresentation(
                id: "invited-user-\(userId)",
                userId: userId,
                chatId: nil,
                title: nil,
                subtitle: "Invited",
                isSpeaking: false,
                isMuted: false,
                isHandRaised: false,
                isInvited: true,
                canRemove: groupCallCoordinator?.groupCall?.isOwned == true
                    && conferenceInvitationMessages[userId] != nil,
            )
        }
        return joined + invited
    }

    var conferenceVideoPresentations: [ConferenceVideoPresentation] {
        guard conferenceIncomingVideoQuality != .audioOnly else { return [] }
        return conferenceParticipants.flatMap { participant -> [ConferenceVideoPresentation] in
            guard !participant.isCurrentUser else { return [] }
            let userId: Int64?
            let chatId: Int64?
            let participantId: String
            switch participant.participantId {
            case .messageSenderUser(let sender):
                userId = sender.userId
                chatId = nil
                participantId = "user-\(sender.userId)"
            case .messageSenderChat(let sender):
                userId = nil
                chatId = sender.chatId
                participantId = "chat-\(sender.chatId)"
            }

            var result = [ConferenceVideoPresentation]()
            if let videoInfo = participant.videoInfo {
                result.append(ConferenceVideoPresentation(
                    id: "camera-\(videoInfo.endpointId)",
                    participantId: participantId,
                    endpointId: videoInfo.endpointId,
                    userId: userId,
                    chatId: chatId,
                    title: nil,
                    isScreenSharing: false,
                    isPaused: videoInfo.isPaused,
                ))
            }
            if let screenSharingVideoInfo = participant.screenSharingVideoInfo {
                result.append(ConferenceVideoPresentation(
                    id: "screen-\(screenSharingVideoInfo.endpointId)",
                    participantId: participantId,
                    endpointId: screenSharingVideoInfo.endpointId,
                    userId: userId,
                    chatId: chatId,
                    title: nil,
                    isScreenSharing: true,
                    isPaused: screenSharingVideoInfo.isPaused,
                ))
            }
            return result
        }
    }

    var conferenceConnectionStatus: String? {
        guard let groupCallCoordinator else { return nil }
        if case .connected = groupCallCoordinator.state {
            return nil
        }
        return "Connecting"
    }

    var conferenceVerificationEmojis: [String] {
        groupCallCoordinator?.verificationEmojis ?? []
    }

    var conferenceInviteURL: URL? {
        guard let inviteLink = groupCallCoordinator?.groupCall?.inviteLink, !inviteLink.isEmpty else { return nil }
        return URL(string: inviteLink)
    }

    var conferenceIncomingVideoQuality: ConferenceIncomingVideoQuality {
        groupCallCoordinator?.incomingVideoQuality ?? .p720
    }

    var conferenceHasIncomingVideo: Bool {
        conferenceParticipants.contains { participant in
            !participant.isCurrentUser
                && (participant.videoInfo != nil || participant.screenSharingVideoInfo != nil)
        }
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
        guard !isRequestingVideo, !showsCameraPreview else { return false }
        if let groupCallCoordinator {
            guard showsConferenceCallUI,
                  case .connected = groupCallCoordinator.state
            else { return false }
            return isScreenSharing || isLocalVideoEnabled || groupCallCoordinator.groupCall?.canEnableVideo == true
        }
        return isLocalVideoEnabled || engineState == .connected || engineState == .reconnecting
    }

    var canToggleMute: Bool {
        guard let groupCallCoordinator else { return true }
        return !isMuted || groupCallCoordinator.canUnmuteSelf
    }

    var shouldShowConferenceRaiseHandControl: Bool {
        guard showsConferenceCallUI,
              let groupCallCoordinator,
              groupCallCoordinator.groupCall?.isVideoChat == true
        else { return false }
        return isMuted && !groupCallCoordinator.canUnmuteSelf
    }

    var isConferenceHandRaised: Bool {
        groupCallCoordinator?.isHandRaised == true
    }

    var canRaiseConferenceHand: Bool {
        guard shouldShowConferenceRaiseHandControl,
              let groupCallCoordinator,
              case .connected = groupCallCoordinator.state
        else { return false }
        return !groupCallCoordinator.isHandRaised && !groupCallCoordinator.isRaisingHand
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

    func joinConference(inviteLink: String, isMuted: Bool) async -> Bool {
        guard activeCall == nil,
              groupCallCoordinator == nil,
              !inviteLink.isEmpty
        else { return false }

        let generation = UUID()
        standaloneConferenceJoinGeneration = generation
        let microphoneGranted = await AVAudioApplication.requestRecordPermission()
        guard standaloneConferenceJoinGeneration == generation,
              activeCall == nil,
              groupCallCoordinator == nil,
              microphoneGranted
        else { return false }

        do {
            Self.prepareAudioSession()
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            log("[GroupCall] couldn't activate standalone audio session: \(error)")
            return false
        }

        isStandaloneConferenceAudioSessionActive = true
        applyEffectiveAudioSessionState()
        self.isMuted = isMuted
        isCallViewMinimized = false
        conferenceHasReplacedPrivateCall = true
        conferenceAudioWasMoved = false

        let coordinator = TelegramGroupCallCoordinator(service: service)
        configureConferenceCallbacks(coordinator)
        groupCallCoordinator = coordinator
        log("[GroupCall] joining standalone conference from invite link")
        coordinator.join(
            inviteLink: inviteLink,
            isMuted: isMuted,
            privateCallEngine: nil,
            audioSessionActive: isEffectiveAudioSessionActive,
            prioritizeVP8: false,
        )
        return true
    }

    func receiveConferenceInvitationPayload(
        chatId: Int64,
        messageId: Int64,
        uniqueId: Int64,
        inviterUserId: Int64?,
        displayTitle: String?,
        isVideo: Bool,
    ) {
        registerIncomingConferenceInvitation(IncomingConferenceInvitation(
            chatId: chatId,
            messageId: messageId,
            uniqueId: uniqueId,
            inviterUserId: inviterUserId,
            displayTitle: displayTitle,
            isVideo: isVideo,
        ))
    }

    func answer() {
        answerActiveCall()
    }

    /// CallKit can deliver Answer before TDLib publishes the call after a cold VoIP wake. Keep the
    /// action and apply it to the first real call rather than fulfilling and losing it.
    func answerFromSystem() {
        if incomingConferenceInvitation != nil {
            answerIncomingConferenceInvitation()
            return
        }
        guard activeCall != nil else {
            pendingSystemAction = .answer
            log("[Call] deferring system Answer until TDLib publishes the call")
            return
        }
        answerActiveCall()
    }

    func end() {
        if isStandaloneConferenceCall, let groupCallCoordinator {
            groupCallCoordinator.leave(endForEveryone: false)
            return
        }
        requestEndCall(endConferenceForEveryone: false)
    }

    func endConferenceForEveryone() {
        guard canEndConferenceForEveryone else {
            end()
            return
        }
        requestEndCall(endConferenceForEveryone: true)
    }

    /// The same cold-wake race applies to End; End takes precedence over an earlier Answer.
    func endFromSystem(completion: @escaping (Bool) -> Void = { _ in }) {
        if let groupCallCoordinator {
            if conferenceHasReplacedPrivateCall {
                let endForEveryone = pendingConferenceEndForEveryone
                pendingConferenceEndForEveryone = false
                groupCallCoordinator.leave(endForEveryone: endForEveryone)
                completion(true)
                return
            }
            resetConferencePreparation(groupCallCoordinator)
        }
        if let invitation = incomingConferenceInvitation {
            declineIncomingConferenceInvitation(invitation, completion: completion)
            return
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
        if isStandaloneConferenceCall {
            setMuted(!isMuted)
            return
        }
        CallKitManager.shared.requestSetMuted(!isMuted)
    }

    func raiseConferenceHand() {
        guard canRaiseConferenceHand else { return }
        groupCallCoordinator?.raiseHand()
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
                let result = try await coordinator.invite(userId: userId, isVideo: isVideo)
                guard groupCallCoordinator === coordinator else { return }
                handleConferenceInvitationResult(result, userId: userId, isVideo: isVideo)
            } catch is CancellationError {
                return
            } catch {
                guard groupCallCoordinator === coordinator else { return }
                conferenceInvitedUserIds.remove(userId)
                conferenceInvitationMessages.removeValue(forKey: userId)
                log("[GroupCall] couldn't invite additional userId=\(userId): \(error)")
                presentConferenceInvitationError("SwiftTG couldn't invite this participant. Please try again.")
            }
            guard groupCallCoordinator === coordinator else { return }
            isInvitingConferenceParticipant = false
            conferenceInviteTask = nil
        }
    }

    func setConferenceParticipantMuted(
        _ participant: ConferenceParticipantPresentation,
        action: ConferenceParticipantMuteAction,
    ) {
        guard conferenceParticipantActionId == nil,
              let coordinator = groupCallCoordinator,
              let groupCallParticipant = conferenceParticipant(id: participant.id)
        else { return }

        let generation = UUID()
        conferenceParticipantActionGeneration = generation
        conferenceParticipantActionId = participant.id
        conferenceParticipantActionTask = Task { [weak self, weak coordinator] in
            guard let self, let coordinator else { return }
            do {
                try await coordinator.setParticipantMuted(
                    groupCallParticipant,
                    isMuted: action.isMuted,
                    forCurrentUser: action.isForCurrentUser,
                )
            } catch is CancellationError {
                return
            } catch {
                log("[GroupCall] couldn't perform \(action.title) for \(participant.id): \(error)")
            }
            guard groupCallCoordinator === coordinator,
                  conferenceParticipantActionGeneration == generation
            else { return }
            conferenceParticipantActionId = nil
            conferenceParticipantActionTask = nil
        }
    }

    func removeConferenceParticipant(_ participant: ConferenceParticipantPresentation) {
        guard conferenceParticipantActionId == nil,
              let userId = participant.userId,
              let coordinator = groupCallCoordinator,
              coordinator.groupCall?.isOwned == true
        else { return }

        let generation = UUID()
        conferenceParticipantActionGeneration = generation
        conferenceParticipantActionId = participant.id
        conferenceParticipantActionTask = Task { [weak self, weak coordinator] in
            guard let self, let coordinator else { return }
            do {
                if participant.isInvited, let invitation = conferenceInvitationMessages[userId] {
                    try await coordinator.cancelInvitation(
                        chatId: invitation.chatId,
                        messageId: invitation.messageId,
                    )
                } else {
                    try await coordinator.removeParticipant(userId: userId)
                }
                guard groupCallCoordinator === coordinator,
                      conferenceParticipantActionGeneration == generation
                else { return }
                conferenceInvitedUserIds.remove(userId)
                conferenceInvitationMessages.removeValue(forKey: userId)
            } catch is CancellationError {
                return
            } catch {
                log("[GroupCall] couldn't remove userId=\(userId): \(error)")
            }
            guard groupCallCoordinator === coordinator,
                  conferenceParticipantActionGeneration == generation
            else { return }
            conferenceParticipantActionId = nil
            conferenceParticipantActionTask = nil
        }
    }

    func requestConferenceVideoView(
        endpointId: String,
        completion: @escaping @MainActor (UIView?) -> Void,
    ) {
        guard let groupCallCoordinator else {
            completion(nil)
            return
        }
        groupCallCoordinator.makeIncomingVideoView(endpointId: endpointId, completion: completion)
    }

    func loadMoreConferenceParticipants() {
        groupCallCoordinator?.loadMoreParticipants()
    }

    func setConferenceIncomingVideoQuality(_ quality: ConferenceIncomingVideoQuality) {
        groupCallCoordinator?.setIncomingVideoQuality(quality)
    }

    func sendConferenceMessage(_ text: String) async -> Bool {
        guard let coordinator = groupCallCoordinator else { return false }
        do {
            try await coordinator.sendMessage(text)
            guard groupCallCoordinator === coordinator else { return false }
            return true
        } catch is CancellationError {
            return false
        } catch {
            guard groupCallCoordinator === coordinator else { return false }
            log("[GroupCall] couldn't send message: \(error)")
            return false
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
        guard canToggleVideo else { return }
        if let coordinator = groupCallCoordinator {
            isRequestingVideo = true
            Task { [weak self, weak coordinator] in
                guard let self, let coordinator else { return }
                let isAuthorized = await Self.requestCameraAccess()
                guard groupCallCoordinator === coordinator else {
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
            return
        }
        guard let callId = activeCall?.id else { return }
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
              activeCall != nil || groupCallCoordinator != nil,
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
        if let groupCallCoordinator {
            groupCallCoordinator.requestVideo(videoCapturer)
        } else {
            engine.requestVideo(videoCapturer)
        }
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

    func dismissCallRating(request: CallRatingRequest) {
        callRatingLogCapture.discard(callId: request.callId)
        guard pendingCallRating?.id == request.id else { return }
        pendingCallRating = nil
    }

    func dismissCallRatingSuccess(token: UUID) {
        guard callRatingSuccessToken == token else { return }
        callRatingSuccessToken = nil
    }

    func minimizeCallView() {
        guard hasActiveCallSurface else { return }
        if isStandaloneConferenceCall {
            isCallViewMinimized = true
            return
        }
        // Never put our own screencast in PiP. Capturing that PiP again creates a feedback loop;
        // Telegram-iOS likewise renders a local "sharing" placeholder instead of the broadcast.
        let hasVideo = (isLocalVideoEnabled && !isScreenSharing) || remoteVideoState != .inactive
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
        restoreCallView(stoppingPictureInPicture: true)
    }

    func submitCallRating(
        request: CallRatingRequest,
        rating: Int,
        problems: [TelegramCallRatingProblem],
        comment: String,
        includeTechnicalInformation: Bool,
    ) async throws {
        guard pendingCallRating?.id == request.id else { return }
        let logURL = includeTechnicalInformation
            ? await callRatingLogCapture.url(callId: request.callId)
            : nil
        try Task.checkCancellation()
        guard pendingCallRating?.id == request.id else { return }
        let feedbackComment = Self.callFeedbackComment(comment: comment, problems: problems)
        _ = try await service.sendCallRating(
            callId: request.callId,
            comment: feedbackComment.isEmpty ? nil : feedbackComment,
            problems: problems,
            rating: rating,
        )

        var shouldRetainLogForUpload = false
        if logURL != nil || !feedbackComment.isEmpty {
            do {
                shouldRetainLogForUpload = try await sendCallFeedbackToSupport(
                    comment: feedbackComment,
                    logURL: logURL,
                )
            } catch {
                // Rating the call is authoritative. Telegram-iOS also sends the technical message
                // as a separate best-effort operation, so a support-upload failure must not submit
                // the rating twice when the user retries.
                if !(error is CancellationError) {
                    log("[Call] couldn't send rating details to Telegram support: \(error)")
                }
            }
        }
        callRatingLogCapture.discard(
            callId: request.callId,
            fileDeletionDelay: shouldRetainLogForUpload ? 300 : 0,
        )
        guard pendingCallRating?.id == request.id else { return }
        pendingCallRating = nil
        if rating < 4 {
            callRatingSuccessToken = UUID()
        }
        log("[Call] sent rating=\(rating) for callId=\(request.callId)")
    }

    // MARK: Private

    private enum PendingSystemAction {
        case answer
        case end
    }

    private struct ConferenceInvitationMessage: Sendable {
        let chatId: Int64
        let messageId: Int64
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
    private static let callFeedbackUserId: Int64 = 4_244_000

    private let service: any TelegramService
    private let conferenceAccessibilityAnnouncer: ConferenceAccessibilityAnnouncer
    private let callRatingLogCapture = CallRatingLogCapture()
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
    private var conferenceParticipantActionTask: Task<Void, Never>?
    private var conferenceTransitionGeneration = UUID()
    private var conferenceParticipantActionGeneration = UUID()
    private var conferenceHasReplacedPrivateCall = false
    private var conferenceAudioWasMoved = false
    private var conferenceInvitedUserIds = Set<Int64>()
    private var conferenceInvitationMessages = [Int64: ConferenceInvitationMessage]()
    private var pendingConferenceEndForEveryone = false
    private var standaloneConferenceJoinGeneration = UUID()
    private var isStandaloneConferenceAudioSessionActive = false
    private var incomingConferenceUsesCallKit = false

    private var hasActiveCallSurface: Bool {
        activeCall != nil || groupCallCoordinator != nil
    }

    private var shouldRouteVideoToSpeaker: Bool {
        activeCall?.isVideo == true
            || isLocalVideoEnabled
            || remoteVideoState != .inactive
            || groupCallCoordinator?.participants.values.contains(where: {
                $0.videoInfo != nil || $0.screenSharingVideoInfo != nil
            }) == true
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

    private nonisolated static func writeTemporaryCallLog(_ callLog: String, callId: Int) -> URL? {
        let url = FileManager.default
            .temporaryDirectory
            .appending(path: "SwiftTG-Call-\(callId)-\(UUID().uuidString).log.json")
        do {
            try Data(callLog.utf8).write(to: url, options: .atomic)
            return url
        } catch {
            log("Error writing temporary call log: \(error)")
            return nil
        }
    }

    private static func isRingingConferenceInvitation(_ content: MessageGroupCall) -> Bool {
        !content.isActive && !content.wasMissed && content.duration == 0
    }

    private static func callFeedbackComment(
        comment: String,
        problems: [TelegramCallRatingProblem],
    ) -> String {
        let hashtags = problems.map { "#\($0.hashtag)" }.joined(separator: " ")
        return [comment, hashtags].filter { !$0.isEmpty }.joined(separator: "\n")
    }

    private func restoreCallView(stoppingPictureInPicture: Bool) {
        guard hasActiveCallSurface else { return }
        isCallViewMinimized = false
        if stoppingPictureInPicture {
            pictureInPictureController?.stop()
        }
    }

    private func requestEndCall(endConferenceForEveryone: Bool) {
        pendingConferenceEndForEveryone = endConferenceForEveryone
        CallKitManager.shared.requestEndCall { [weak self] in
            self?.pendingConferenceEndForEveryone = false
        }
    }

    private func sendCallFeedbackToSupport(comment: String, logURL: URL?) async throws -> Bool {
        let chat = try await service.createPrivateChat(force: false, userId: Self.callFeedbackUserId)
        let formattedComment = FormattedText(entities: [], text: comment)
        let content: InputMessageContent =
            if let logURL {
                TelegramMessageSending.documentContent(url: logURL, caption: formattedComment)
            } else {
                TelegramMessageSending.textContent(formattedComment)
            }
        _ = try await TelegramMessageSending.send(
            service: service,
            chatId: chat.id,
            contents: [content],
            replyTo: nil,
        )
        return logURL != nil
    }

    private func deactivateStandaloneConferenceAudioSessionIfNeeded() {
        standaloneConferenceJoinGeneration = UUID()
        guard isStandaloneConferenceAudioSessionActive else { return }
        isStandaloneConferenceAudioSessionActive = false
        applyEffectiveAudioSessionState()
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            log("[GroupCall] couldn't deactivate standalone audio session: \(error)")
        }
    }

    private func conferenceParticipant(id: String) -> GroupCallParticipant? {
        conferenceParticipants.first { participant in
            switch participant.participantId {
            case .messageSenderUser(let sender):
                id == "user-\(sender.userId)"
            case .messageSenderChat(let sender):
                id == "chat-\(sender.chatId)"
            }
        }
    }

    private func conferenceMuteAction(
        for participant: GroupCallParticipant,
    ) -> ConferenceParticipantMuteAction? {
        guard !participant.isCurrentUser else { return nil }
        if participant.isMutedForCurrentUser, participant.canBeUnmutedForCurrentUser {
            return .unmuteForCurrentUser
        }
        if participant.isMutedForAllUsers {
            return participant.canBeUnmutedForAllUsers ? .allowToSpeak : nil
        }
        if participant.canBeMutedForAllUsers {
            return .mute
        }
        if participant.canBeMutedForCurrentUser {
            return .muteForCurrentUser
        }
        return nil
    }

    private func handleConferenceInvitationResult(
        _ result: InviteGroupCallParticipantResult,
        userId: Int64,
        isVideo: Bool,
    ) {
        switch result {
        case .inviteGroupCallParticipantResultSuccess(let success):
            conferenceInvitationMessages[userId] = ConferenceInvitationMessage(
                chatId: success.chatId,
                messageId: success.messageId,
            )
            log("[GroupCall] invited userId=\(userId) video=\(isVideo)")
        case .inviteGroupCallParticipantResultUserAlreadyParticipant:
            conferenceInvitedUserIds.remove(userId)
            conferenceInvitationMessages.removeValue(forKey: userId)
            log("[GroupCall] userId=\(userId) is already a participant")
        case .inviteGroupCallParticipantResultUserPrivacyRestricted:
            conferenceInvitedUserIds.remove(userId)
            conferenceInvitationMessages.removeValue(forKey: userId)
            log("[GroupCall] userId=\(userId) couldn't be invited because of privacy settings")
            presentConferenceInvitationError("This user can't be invited because of their privacy settings.")
        case .inviteGroupCallParticipantResultUserWasBanned:
            conferenceInvitedUserIds.remove(userId)
            conferenceInvitationMessages.removeValue(forKey: userId)
            log("[GroupCall] userId=\(userId) couldn't be invited because they are banned")
            presentConferenceInvitationError("This user can't be invited because they were removed from the call.")
        }
    }

    private func presentConferenceInvitationError(_ message: String) {
        conferenceInvitationErrorMessage = message
        showsConferenceInvitationError = true
    }

    private func handleConferenceInvitationUpdate(_ update: Update) {
        switch update {
        case .updateNewMessage(let value):
            let message = value.message
            guard !message.isOutgoing,
                  case .messageGroupCall(let content) = message.content
            else { return }
            if Self.isRingingConferenceInvitation(content) {
                let inviterUserId: Int64? =
                    if case .messageSenderUser(let sender) = message.senderId {
                        sender.userId
                    } else {
                        nil
                    }
                registerIncomingConferenceInvitation(IncomingConferenceInvitation(
                    chatId: message.chatId,
                    messageId: message.id,
                    uniqueId: content.uniqueId.rawValue,
                    inviterUserId: inviterUserId,
                    displayTitle: nil,
                    isVideo: content.isVideo,
                ))
            }
        case .updateMessageContent(let value):
            guard let invitation = incomingConferenceInvitation,
                  invitation.chatId == value.chatId,
                  invitation.messageId == value.messageId
            else { return }
            guard case .messageGroupCall(let content) = value.newContent,
                  Self.isRingingConferenceInvitation(content)
            else {
                finishIncomingConferenceInvitation(reason: .unanswered)
                return
            }
        case .updateDeleteMessages(let value):
            guard let invitation = incomingConferenceInvitation,
                  invitation.chatId == value.chatId,
                  value.messageIds.contains(invitation.messageId)
            else { return }
            finishIncomingConferenceInvitation(reason: .unanswered)
        default:
            break
        }
    }

    private func registerIncomingConferenceInvitation(_ invitation: IncomingConferenceInvitation) {
        guard activeCall == nil, groupCallCoordinator == nil else {
            log("[GroupCall] ignoring incoming conference invitation while another call is active")
            return
        }
        guard incomingConferenceInvitation != invitation else { return }
        incomingConferenceInvitation = invitation
        incomingConferenceUsesCallKit = true
        Self.prepareAudioSession()
        log(
            "[GroupCall] incoming invitation chatId=\(invitation.chatId) messageId=\(invitation.messageId)",
        )
        onIncomingConferenceInvitation?(invitation)

        if pendingSystemAction == .end {
            pendingSystemAction = nil
            declineIncomingConferenceInvitation(invitation)
        } else if pendingSystemAction == .answer {
            pendingSystemAction = nil
            answerIncomingConferenceInvitation()
        }
    }

    private func answerIncomingConferenceInvitation() {
        guard let invitation = incomingConferenceInvitation,
              activeCall == nil,
              groupCallCoordinator == nil
        else { return }

        incomingConferenceInvitation = nil
        isMuted = false
        isCallViewMinimized = false
        conferenceHasReplacedPrivateCall = true
        conferenceAudioWasMoved = false

        let coordinator = TelegramGroupCallCoordinator(service: service)
        configureConferenceCallbacks(coordinator)
        groupCallCoordinator = coordinator
        log(
            "[GroupCall] accepting invitation chatId=\(invitation.chatId) messageId=\(invitation.messageId)",
        )
        coordinator.join(
            invitationChatId: invitation.chatId,
            invitationMessageId: invitation.messageId,
            isMuted: false,
            audioSessionActive: isEffectiveAudioSessionActive,
            prioritizeVP8: false,
        )
    }

    private func declineIncomingConferenceInvitation(
        _ invitation: IncomingConferenceInvitation,
        completion: @escaping (Bool) -> Void = { _ in },
    ) {
        Task { [weak self] in
            guard let self else {
                completion(false)
                return
            }
            do {
                _ = try await service.declineGroupCallInvitation(
                    chatId: invitation.chatId,
                    messageId: invitation.messageId,
                )
            } catch is CancellationError {
                completion(false)
                return
            } catch {
                log("[GroupCall] couldn't decline incoming invitation: \(error)")
            }
            guard incomingConferenceInvitation == invitation else {
                completion(true)
                return
            }
            incomingConferenceInvitation = nil
            incomingConferenceUsesCallKit = false
            pendingSystemAction = nil
            onCallEnded?(.unanswered)
            completion(true)
        }
    }

    private func finishIncomingConferenceInvitation(reason: EndReason) {
        guard incomingConferenceInvitation != nil else { return }
        incomingConferenceInvitation = nil
        pendingSystemAction = nil
        let notifyCallKit = incomingConferenceUsesCallKit
        incomingConferenceUsesCallKit = false
        if notifyCallKit {
            onCallEnded?(reason)
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
            if let previousCallId = pendingCallRating?.callId, previousCallId != ratingRequest?.callId {
                callRatingLogCapture.discard(callId: previousCallId)
            }
            if let ratingRequest {
                callRatingLogCapture.begin(callId: ratingRequest.callId)
            }
            finishCurrentCall(
                notifyCallKit: true,
                endReason: Self.endReason(for: call.state),
                terminalTone: Self.terminalTone(for: call.state),
                debugInformationCallId: debugInformationCallId,
                logCallId: logCallId,
                ratingLogCallId: ratingRequest?.callId,
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
            if let previousCallId = pendingCallRating?.callId {
                callRatingLogCapture.discard(callId: previousCallId)
            }
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
        conferenceAccessibilityAnnouncer.reset()
        coordinator.onConnected = { [weak self, weak coordinator] in
            guard let self, let coordinator, groupCallCoordinator === coordinator else { return }
            moveAudioToConferenceIfReady()
        }
        coordinator.onSignalBarsChanged = { [weak self, weak coordinator] bars in
            guard let self, let coordinator, groupCallCoordinator === coordinator else { return }
            signalBars = bars
        }
        coordinator.onLocalVideoFailed = { [weak self, weak coordinator] in
            guard let self, let coordinator, groupCallCoordinator === coordinator else { return }
            handleConferenceLocalVideoFailure()
        }
        coordinator.onScreenSharingFailed = { [weak self, weak coordinator] in
            guard let self, let coordinator, groupCallCoordinator === coordinator else { return }
            handleConferenceScreenSharingFailure()
        }
        coordinator.onLocalMuteStateChanged = { [weak self, weak coordinator] muted in
            guard let self, let coordinator, groupCallCoordinator === coordinator else { return }
            handleConferenceLocalMuteStateChanged(muted)
        }
        coordinator.onParticipantChanged = { [weak self, weak coordinator] previous, current in
            guard let self, let coordinator, groupCallCoordinator === coordinator else { return }
            if let current, case .messageSenderUser(let sender) = current.participantId {
                conferenceInvitedUserIds.remove(sender.userId)
                conferenceInvitationMessages.removeValue(forKey: sender.userId)
            }
            conferenceAccessibilityAnnouncer.participantChanged(
                previous: previous,
                current: current,
            )
            if let previous,
               let current,
               current.isCurrentUser,
               !previous.canUnmuteSelf,
               current.canUnmuteSelf,
               previous.isHandRaised,
               UIAccessibility.isVoiceOverRunning
            {
                UIAccessibility.post(notification: .announcement, argument: "You can now speak")
            }
            updateVideoAudioRouting()
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
                    let result = try await coordinator.invite(
                        userId: invitedUserId,
                        isVideo: invitedWithVideo,
                    )
                    guard conferenceTransitionGeneration == generation,
                          groupCallCoordinator === coordinator
                    else { return }
                    handleConferenceInvitationResult(
                        result,
                        userId: invitedUserId,
                        isVideo: invitedWithVideo,
                    )
                } catch is CancellationError {
                    return
                } catch {
                    guard conferenceTransitionGeneration == generation,
                          groupCallCoordinator === coordinator
                    else { return }
                    conferenceInvitedUserIds.remove(invitedUserId)
                    conferenceInvitationMessages.removeValue(forKey: invitedUserId)
                    log("[GroupCall] couldn't invite userId=\(invitedUserId): \(error)")
                    presentConferenceInvitationError("SwiftTG couldn't invite this participant. Please try again.")
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
        conferenceAccessibilityAnnouncer.enableAfterInitialSnapshot()
        let preservedLocalMedia: Bool
        if isScreenSharing, let screenShareCapturer {
            coordinator.startScreenSharing(screenShareCapturer)
            preservedLocalMedia = true
            log("[GroupCall] transferred local screen sharing from the private call")
        } else if isLocalVideoEnabled, let videoCapturer {
            coordinator.requestVideo(videoCapturer)
            preservedLocalMedia = true
            log("[GroupCall] transferred local camera from the private call")
        } else {
            preservedLocalMedia = false
        }
        finishPrivateEngineTransition(preservingLocalMedia: preservedLocalMedia)
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
        conferenceParticipantActionTask?.cancel()
        conferenceParticipantActionTask = nil
        conferenceTransitionGeneration = UUID()
        conferenceParticipantActionGeneration = UUID()
        groupCallCoordinator = nil
        isUpgradingToConference = false
        isInvitingConferenceParticipant = false
        conferenceParticipantActionId = nil
        conferenceHasReplacedPrivateCall = false
        conferenceAudioWasMoved = false
        conferenceInvitedUserIds.removeAll()
        conferenceInvitationMessages.removeAll()
        pendingConferenceEndForEveryone = false
        deactivateStandaloneConferenceAudioSessionIfNeeded()
    }

    private func finishPrivateEngineTransition(preservingLocalMedia: Bool) {
        engineStartTask?.cancel()
        engineStartTask = nil
        engineStartCallId = nil
        if !preservingLocalMedia {
            screenShareReceiver?.stop()
            screenShareReceiver = nil
            screenShareCapturer = nil
            isScreenSharing = false
        }
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
        if !preservingLocalMedia {
            isLocalVideoEnabled = false
            localVideoView = nil
            videoCapturer = nil
            videoGeneration = UUID()
            isUsingFrontCamera = true
        }
        cameraPreviewView = nil
        remoteVideoView = nil
        isRequestingRemoteVideoView = false
        remoteVideoGeneration = UUID()
        showsCameraPreview = false
        showsCameraPermissionAlert = false
        updateVideoAudioRouting()
    }

    private func finishConference(
        _ coordinator: TelegramGroupCallCoordinator,
        endReason: EndReason,
    ) {
        guard groupCallCoordinator === coordinator else { return }
        let notifyIncomingConferenceCallKit = incomingConferenceUsesCallKit
        clearConferenceCallbacks(coordinator)
        conferenceTransitionTask?.cancel()
        conferenceTransitionTask = nil
        conferenceInviteTask?.cancel()
        conferenceInviteTask = nil
        conferenceParticipantActionTask?.cancel()
        conferenceParticipantActionTask = nil
        conferenceTransitionGeneration = UUID()
        conferenceParticipantActionGeneration = UUID()
        groupCallCoordinator = nil
        isUpgradingToConference = false
        isInvitingConferenceParticipant = false
        conferenceParticipantActionId = nil
        conferenceHasReplacedPrivateCall = false
        conferenceAudioWasMoved = false
        conferenceInvitedUserIds.removeAll()
        conferenceInvitationMessages.removeAll()
        incomingConferenceUsesCallKit = false
        pendingConferenceEndForEveryone = false
        deactivateStandaloneConferenceAudioSessionIfNeeded()
        finishCurrentCall(notifyCallKit: true, endReason: endReason)
        if notifyIncomingConferenceCallKit {
            onCallEnded?(endReason)
        }
    }

    private func clearConferenceCallbacks(_ coordinator: TelegramGroupCallCoordinator) {
        coordinator.onPrepared = nil
        coordinator.onConnected = nil
        coordinator.onSignalBarsChanged = nil
        coordinator.onLocalVideoFailed = nil
        coordinator.onScreenSharingFailed = nil
        coordinator.onLocalMuteStateChanged = nil
        coordinator.onParticipantChanged = nil
        coordinator.onFailed = nil
        coordinator.onEnded = nil
        conferenceAccessibilityAnnouncer.reset()
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
        let hasActiveAudioSession = isCallKitAudioSessionActive || isStandaloneConferenceAudioSessionActive
        let active = hasActiveAudioSession && !isAudioInterrupted && areMediaServicesAvailable
        guard active != isEffectiveAudioSessionActive else { return }
        isEffectiveAudioSessionActive = active
        log(
            "[Call] audio session effective=\(active) CallKit=\(isCallKitAudioSessionActive) interrupted=\(isAudioInterrupted) mediaServices=\(areMediaServicesAvailable)",
        )
        engine.setAudioSessionActive(active)
        groupCallCoordinator?.setAudioSessionActive(active)
        if active,
           groupCallCoordinator == nil,
           let call = activeCall,
           case .callStateReady(let info) = call.state,
           !isEngineRunning,
           engineStartCallId == nil
        {
            startEngine(call: call, info: info)
        }
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
        guard isEffectiveAudioSessionActive else {
            log("[Call] deferring native call context until CallKit activates the audio session")
            return
        }
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
        engine.setTone(call.isVideo ? nil : Self.connectingTone)
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
            engine.setTone(activeCall?.isVideo == true ? nil : Self.connectingTone)
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
        if hasActiveCallSurface, shouldRouteVideoToSpeaker {
            if device.isProximityMonitoringEnabled {
                device.isProximityMonitoringEnabled = false
                log("[Call] proximity monitoring force-disabled for video")
            }
            ownsProximityMonitoring = false
            return
        }

        let shouldMonitor = hasActiveCallSurface
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
        guard hasActiveCallSurface, shouldRouteVideoToSpeaker else {
            videoAudioRouteTask?.cancel()
            videoAudioRouteTask = nil
            updateProximityMonitoring()
            return
        }

        routeVideoToSpeakerIfNeeded()
        updateProximityMonitoring()
        guard videoAudioRouteTask == nil else { return }

        videoAudioRouteTask = Task { [weak self] in
            while let self, !Task.isCancelled, hasActiveCallSurface, shouldRouteVideoToSpeaker {
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
        guard hasActiveCallSurface,
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
        if hasActiveCallSurface {
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
                if let groupCallCoordinator {
                    groupCallCoordinator.addScreenSharingAudioData(data)
                } else {
                    engine.addExternalAudioData(data)
                }
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
            videoGeneration = UUID()
            screenShareCapturer = capturer
            isScreenSharing = true
            isLocalVideoEnabled = true
            isUsingFrontCamera = true
            localVideoView = nil
            updateVideoAudioRouting()
            if let groupCallCoordinator {
                groupCallCoordinator.startScreenSharing(capturer)
            } else {
                engine.requestVideo(capturer)
            }
            refreshPictureInPictureController()
            log("[Call] screen sharing started")
        } else {
            if let groupCallCoordinator {
                groupCallCoordinator.stopScreenSharing()
            } else {
                engine.disableVideo()
            }
            clearScreenSharingState()
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
        if let groupCallCoordinator {
            groupCallCoordinator.disableVideo()
        } else {
            engine.disableVideo()
        }
        clearLocalVideoState()
    }

    private func handleConferenceLocalVideoFailure() {
        guard isLocalVideoEnabled else { return }
        log("[GroupCall] clearing local video after rejoin failure")
        clearLocalVideoState()
    }

    private func handleConferenceScreenSharingFailure() {
        guard isScreenSharing else { return }
        log("[GroupCall] stopping local broadcast after screen-sharing join failure")
        screenShareReceiver?.requestBroadcastStop()
        clearScreenSharingState()
    }

    private func handleConferenceLocalMuteStateChanged(_ muted: Bool) {
        guard isMuted != muted else { return }
        isMuted = muted
        guard !isStandaloneConferenceCall else { return }
        engine.setMuted(muted)
        CallKitManager.shared.requestSetMuted(muted)
    }

    private func clearScreenSharingState() {
        videoGeneration = UUID()
        screenShareCapturer = nil
        isScreenSharing = false
        isLocalVideoEnabled = false
        localVideoView = nil
        updateVideoAudioRouting()
        refreshPictureInPictureController()
    }

    private func clearLocalVideoState() {
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
        } else if isLocalVideoEnabled, !isScreenSharing {
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
            // AVKit is already stopping PiP while it asks us to restore the interface. Calling
            // `stopPictureInPicture()` again from this delegate callback is reentrant.
            restoreCallView(stoppingPictureInPicture: false)
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
        ratingLogCallId: Int? = nil,
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
        if debugInformationCallId != nil || logCallId != nil || ratingLogCallId != nil {
            let service = service
            let callRatingLogCapture = callRatingLogCapture
            engine.stop(finalTone: finalTone, retainAudioDeviceFor: retentionDuration) { result in
                let ratingLogURL = ratingLogCallId.flatMap { callId in
                    result?.callLog.flatMap { Self.writeTemporaryCallLog($0, callId: callId) }
                }
                let requestedLogURL = logCallId.flatMap { callId in
                    result?.callLog.flatMap { Self.writeTemporaryCallLog($0, callId: callId) }
                }
                if let ratingLogCallId {
                    callRatingLogCapture.finish(callId: ratingLogCallId, url: ratingLogURL)
                }
                guard let result else { return }
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
                    if let logCallId, let requestedLogURL {
                        do {
                            _ = try await service.sendCallLog(callId: logCallId, path: requestedLogURL.path)
                            log("[Call] sent requested call log for callId=\(logCallId)")
                        } catch {
                            log("Error sending call log: \(error)")
                        }
                        try? FileManager.default.removeItem(at: requestedLogURL)
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
        ratingLogCallId: Int? = nil,
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
            ratingLogCallId: ratingLogCallId,
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
