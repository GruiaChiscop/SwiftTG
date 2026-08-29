// TelegramGroupCallCoordinator.swift

import Combine
import Foundation
import Observation
import TDLibKit
@preconcurrency import TgVoipWebrtc
import UIKit

// MARK: - TelegramGroupCallCoordinator

/// Coordinates TDLib's standalone group-call lifecycle with the tgcalls media context. UI and
/// CallKit integration deliberately sit above this type so a private call can keep its system call
/// identity while its media transport is migrated.
@MainActor
@Observable final class TelegramGroupCallCoordinator {
    // MARK: Lifecycle

    init(service: any TelegramService) {
        self.service = service
        service.updatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] update in
                self?.handle(update)
            }
            .store(in: &cancellables)
    }

    // MARK: Internal

    enum State: Equatable {
        case idle
        case preparing
        case connecting(groupCallId: Int, inviteLink: String)
        case connected(groupCallId: Int, inviteLink: String)
        case failed
        case ended
    }

    struct PreparedCall: Equatable, Sendable {
        let groupCallId: Int
        let inviteLink: String
    }

    private(set) var state = State.idle
    private(set) var groupCall: GroupCall?
    private(set) var participants = [MessageSender: GroupCallParticipant]()
    private(set) var messages = [Int: GroupCallMessage]()
    private(set) var verificationEmojis = [String]()
    private(set) var signalBars: Int?
    private(set) var speakingAudioSourceIds = Set<UInt32>()
    private(set) var isLocalVideoEnabled = false
    private(set) var isScreenSharing = false
    private(set) var canUnmuteSelf = true
    private(set) var isUpdatingHandRaised = false
    private(set) var incomingVideoQuality = ConferenceIncomingVideoQuality.p720
    private(set) var messageCharacterLimit = 128

    var onPrepared: ((PreparedCall) -> Void)?
    var onConnected: (() -> Void)?
    var onSignalBarsChanged: ((Int) -> Void)?
    var onFailed: (() -> Void)?
    var onEnded: (() -> Void)?
    var onLocalVideoFailed: (() -> Void)?
    var onScreenSharingFailed: (() -> Void)?
    var onLocalMuteStateChanged: ((Bool) -> Void)?
    var onParticipantChanged: ((GroupCallParticipant?, GroupCallParticipant?) -> Void)?

    var isHandRaised: Bool {
        participants.values.first(where: \.isCurrentUser)?.isHandRaised == true
    }

    func create(
        isMuted: Bool,
        privateCallEngine: TelegramCallEngine?,
        audioSessionActive: Bool,
        prioritizeVP8: Bool,
    ) {
        begin(
            mode: .create,
            isMuted: isMuted,
            privateCallEngine: privateCallEngine,
            audioSessionActive: audioSessionActive,
            prioritizeVP8: prioritizeVP8,
        )
    }

    func join(
        inviteLink: String,
        isMuted: Bool,
        privateCallEngine: TelegramCallEngine?,
        audioSessionActive: Bool,
        prioritizeVP8: Bool,
    ) {
        join(
            inputGroupCall: .inputGroupCallLink(.init(link: inviteLink)),
            isMuted: isMuted,
            privateCallEngine: privateCallEngine,
            audioSessionActive: audioSessionActive,
            prioritizeVP8: prioritizeVP8,
        )
    }

    func join(
        invitationChatId: Int64,
        invitationMessageId: Int64,
        isMuted: Bool,
        audioSessionActive: Bool,
        prioritizeVP8: Bool,
    ) {
        join(
            inputGroupCall: .inputGroupCallMessage(.init(
                chatId: invitationChatId,
                messageId: invitationMessageId,
            )),
            isMuted: isMuted,
            privateCallEngine: nil,
            audioSessionActive: audioSessionActive,
            prioritizeVP8: prioritizeVP8,
        )
    }

    func join(
        inputGroupCall: InputGroupCall,
        isMuted: Bool,
        privateCallEngine: TelegramCallEngine?,
        audioSessionActive: Bool,
        prioritizeVP8: Bool,
    ) {
        begin(
            mode: .join(inputGroupCall),
            isMuted: isMuted,
            privateCallEngine: privateCallEngine,
            audioSessionActive: audioSessionActive,
            prioritizeVP8: prioritizeVP8,
        )
    }

    func joinVideoChat(
        groupCallId: Int,
        inviteHash: String? = nil,
        participantId: MessageSender? = nil,
        isMuted: Bool,
        audioSessionActive: Bool,
        prioritizeVP8: Bool,
    ) {
        begin(
            mode: .videoChat(
                groupCallId: groupCallId,
                inviteHash: inviteHash,
                participantId: participantId,
            ),
            isMuted: isMuted,
            privateCallEngine: nil,
            audioSessionActive: audioSessionActive,
            prioritizeVP8: prioritizeVP8,
        )
    }

    func invite(userId: Int64, isVideo: Bool) async throws -> InviteGroupCallParticipantResult {
        guard let groupCallId = groupCall?.id else {
            throw CoordinatorError.notReady
        }
        if groupCall?.isVideoChat == true {
            _ = try await service.inviteVideoChatParticipants(
                groupCallId: groupCallId,
                userIds: [userId],
            )
            return .inviteGroupCallParticipantResultSuccess(.init(chatId: 0, messageId: 0))
        }
        return try await service.inviteGroupCallParticipant(
            groupCallId: groupCallId,
            isVideo: isVideo,
            userId: userId,
        )
    }

    func cancelInvitation(chatId: Int64, messageId: Int64) async throws {
        _ = try await service.declineGroupCallInvitation(chatId: chatId, messageId: messageId)
    }

    func loadMoreParticipants() {
        guard !isLoadingMoreParticipants,
              let groupCall,
              !groupCall.loadedAllParticipants
        else { return }
        isLoadingMoreParticipants = true
        let generation = operationGeneration
        let groupCallId = groupCall.id
        participantLoadingTask?.cancel()
        participantLoadingTask = Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await service.loadGroupCallParticipants(groupCallId: groupCallId, limit: 100)
            } catch is CancellationError {
                return
            } catch {
                guard operationGeneration == generation, self.groupCall?.id == groupCallId else { return }
                log("[GroupCall] couldn't load more participants: \(error)")
            }
            guard operationGeneration == generation, self.groupCall?.id == groupCallId else { return }
            isLoadingMoreParticipants = false
            participantLoadingTask = nil
        }
    }

    func setParticipantMuted(
        _ participant: GroupCallParticipant,
        isMuted: Bool,
        forCurrentUser: Bool,
    ) async throws {
        guard let groupCallId = groupCall?.id else {
            throw CoordinatorError.notReady
        }
        if forCurrentUser {
            setParticipantVolume(participant, mutedForCurrentUser: isMuted)
        }
        do {
            _ = try await service.toggleGroupCallParticipantIsMuted(
                groupCallId: groupCallId,
                isMuted: isMuted,
                participantId: participant.participantId,
            )
        } catch {
            if forCurrentUser {
                setParticipantVolume(
                    participant,
                    mutedForCurrentUser: participant.isMutedForCurrentUser,
                )
            }
            throw error
        }
    }

    func setParticipantVolumeLevel(
        _ participant: GroupCallParticipant,
        volumeLevel: Int,
        synchronize: Bool,
    ) {
        guard let groupCall,
              participants[participant.participantId] != nil
        else { return }

        let boundedVolumeLevel = min(20000, max(0, volumeLevel))
        applyParticipantVolume(participant, volumeLevel: boundedVolumeLevel)
        guard synchronize, boundedVolumeLevel > 0 else { return }

        volumeUpdateTask?.cancel()
        let generation = operationGeneration
        let groupCallId = groupCall.id
        let participantId = participant.participantId
        volumeUpdateTask = Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await service.setGroupCallParticipantVolumeLevel(
                    groupCallId: groupCallId,
                    participantId: participantId,
                    volumeLevel: boundedVolumeLevel,
                )
            } catch is CancellationError {
                return
            } catch {
                guard operationGeneration == generation,
                      self.groupCall?.id == groupCallId,
                      let currentParticipant = participants[participantId]
                else { return }
                setParticipantVolume(
                    currentParticipant,
                    mutedForCurrentUser: currentParticipant.isMutedForCurrentUser,
                )
                log("[GroupCall] couldn't update participant volume: \(error)")
            }
            guard operationGeneration == generation,
                  self.groupCall?.id == groupCallId
            else { return }
            volumeUpdateTask = nil
        }
    }

    func removeParticipant(userId: Int64) async throws {
        guard let groupCall, groupCall.isOwned else {
            throw CoordinatorError.notReady
        }
        _ = try await service.banGroupCallParticipants(
            groupCallId: groupCall.id,
            userIds: [TdInt64(userId)],
        )
    }

    func sendMessage(_ text: String) async throws {
        guard let groupCall,
              groupCall.areMessagesAllowed,
              groupCall.canSendMessages
        else {
            throw CoordinatorError.notReady
        }
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        guard trimmedText.count <= messageCharacterLimit else {
            throw CoordinatorError.messageTooLong
        }
        let generation = operationGeneration
        let groupCallId = groupCall.id
        let entities = try await service.getTextEntities(text: trimmedText).entities
        guard operationGeneration == generation,
              self.groupCall?.id == groupCallId
        else {
            throw CancellationError()
        }
        _ = try await service.sendGroupCallMessage(
            groupCallId: groupCallId,
            paidMessageStarCount: nil,
            text: FormattedText(entities: entities, text: trimmedText),
        )
    }

    func setMuted(_ muted: Bool) {
        guard muted || canUnmuteSelf else {
            engine.setMuted(true)
            onLocalMuteStateChanged?(true)
            return
        }
        guard isMuted != muted else {
            engine.setMuted(muted)
            return
        }
        let previousValue = isMuted
        isMuted = muted
        engine.setMuted(muted)
        guard case .connected = state,
              let groupCallId = groupCall?.id,
              let participantId = participants.values.first(where: \.isCurrentUser)?.participantId
        else { return }

        muteUpdateTask?.cancel()
        let generation = operationGeneration
        let updateGeneration = UUID()
        muteUpdateGeneration = updateGeneration
        pendingMutedValue = muted
        muteUpdateTask = Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await service.toggleGroupCallParticipantIsMuted(
                    groupCallId: groupCallId,
                    isMuted: muted,
                    participantId: participantId,
                )
                guard operationGeneration == generation,
                      muteUpdateGeneration == updateGeneration
                else { return }
                pendingMutedValue = nil
            } catch is CancellationError {
                return
            } catch {
                guard operationGeneration == generation,
                      muteUpdateGeneration == updateGeneration
                else { return }
                pendingMutedValue = nil
                isMuted = previousValue
                engine.setMuted(previousValue)
                log("[GroupCall] failed to update local mute state to \(muted): \(error)")
                onLocalMuteStateChanged?(previousValue)
            }
            guard operationGeneration == generation,
                  muteUpdateGeneration == updateGeneration
            else { return }
            muteUpdateTask = nil
        }
    }

    func raiseHand() {
        setHandRaised(true)
    }

    func lowerHand() {
        setHandRaised(false)
    }

    func requestVideo(_ capturer: OngoingCallThreadLocalContextVideoCapturer) {
        let generation = operationGeneration
        engine.requestVideo(capturer) { [weak self] payload, audioSourceId in
            Task { @MainActor [weak self] in
                self?.submitVideoRejoin(
                    payload: payload,
                    audioSourceId: audioSourceId,
                    isVideoEnabled: true,
                    generation: generation,
                )
            }
        }
    }

    func disableVideo() {
        let generation = operationGeneration
        engine.disableVideo { [weak self] payload, audioSourceId in
            Task { @MainActor [weak self] in
                self?.submitVideoRejoin(
                    payload: payload,
                    audioSourceId: audioSourceId,
                    isVideoEnabled: false,
                    generation: generation,
                )
            }
        }
    }

    func startScreenSharing(_ capturer: OngoingCallThreadLocalContextVideoCapturer) {
        guard case .connected = state, let encryptionBridge else {
            onScreenSharingFailed?()
            return
        }
        // A video chat's screencast is server-mixed like its main media - no E2E, plain transport.
        let isVideoChat = groupCall?.isVideoChat == true
        let generation = operationGeneration
        let screenSharingGeneration = UUID()
        self.screenSharingGeneration = screenSharingGeneration
        screenSharingTask?.cancel()
        screencastEngine.start(
            capturer: capturer,
            encryption: isVideoChat ? nil : encryptionBridge.makeEncryption(channel: .screenSharing),
            isConference: !isVideoChat,
        ) { [weak self] payload, audioSourceId in
            Task { @MainActor [weak self] in
                self?.submitScreenSharingJoin(
                    payload: payload,
                    audioSourceId: audioSourceId,
                    generation: generation,
                    screenSharingGeneration: screenSharingGeneration,
                )
            }
        }
    }

    func addScreenSharingAudioData(_ data: Data) {
        screencastEngine.addExternalAudioData(data)
    }

    func stopScreenSharing() {
        screencastEngine.stop()
        isScreenSharing = false
        screenSharingTask?.cancel()
        screenSharingTask = nil
        screenSharingGeneration = UUID()
        guard let groupCallId = groupCall?.id else { return }
        let generation = operationGeneration
        screenSharingTask = Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await service.endGroupCallScreenSharing(groupCallId: groupCallId)
            } catch is CancellationError {
                return
            } catch {
                guard operationGeneration == generation else { return }
                log("[GroupCall] failed to end screen sharing for groupCallId=\(groupCallId): \(error)")
            }
            guard operationGeneration == generation else { return }
            screenSharingTask = nil
        }
    }

    func setAudioSessionActive(_ active: Bool) {
        engine.setAudioSessionActive(active)
    }

    func setIncomingVideoQuality(_ quality: ConferenceIncomingVideoQuality) {
        guard incomingVideoQuality != quality else { return }
        incomingVideoQuality = quality
        refreshMediaChannels()
    }

    func setCentralVideo(endpointId: String?, isExpanded: Bool) {
        guard centralVideoEndpointId != endpointId || hasCentralVideo != isExpanded else { return }
        centralVideoEndpointId = endpointId
        hasCentralVideo = isExpanded
        refreshMediaChannels()
    }

    func activateIncomingAudio() {
        engine.activateIncomingAudio()
    }

    func makeIncomingVideoView(
        endpointId: String,
        completion: @escaping @MainActor (UIView?) -> Void,
    ) {
        engine.makeIncomingVideoView(endpointId: endpointId, completion: completion)
    }

    func leave(endForEveryone: Bool) {
        let generation = beginNewOperation()
        guard let groupCallId = groupCall?.id else {
            reset(to: .ended)
            return
        }
        operationTask = Task { [weak self] in
            guard let self else { return }
            do {
                _ =
                    if endForEveryone, groupCall?.isOwned == true {
                        try await service.endGroupCall(groupCallId: groupCallId)
                    } else {
                        try await service.leaveGroupCall(groupCallId: groupCallId)
                    }
            } catch {
                log("[GroupCall] leave failed for groupCallId=\(groupCallId): \(error)")
            }
            guard operationGeneration == generation else { return }
            reset(to: .ended)
        }
    }

    func cancel() {
        reset(to: .idle)
    }

    // MARK: Private

    private enum Mode: Sendable {
        case create
        case join(InputGroupCall)
        case videoChat(groupCallId: Int, inviteHash: String?, participantId: MessageSender?)
    }

    private enum CoordinatorError: Swift.Error {
        case notReady
        case messageTooLong
    }

    private struct EnginePreferences {
        var outgoingAudioBitrateKbit: Int32?
        var prioritizeVP8 = false
        var useReferenceImpl = false
    }

    private let service: any TelegramService
    private let engine = TelegramGroupCallEngine()
    private let screencastEngine = TelegramGroupCallScreencastEngine()
    private var encryptionBridge: TelegramGroupCallEncryptionBridge?
    private var cancellables = Set<AnyCancellable>()
    private var operationTask: Task<Void, Never>?
    private var enginePreparationTask: Task<Void, Never>?
    private var operationGeneration = UUID()
    private var currentJoinMode: Mode?
    private var rejoinTask: Task<Void, Never>?
    private var rejoinRetryTask: Task<Void, Never>?
    private var rejoinGeneration = UUID()
    private var isRequestingRejoinPayload = false
    private var participantLoadingTask: Task<Void, Never>?
    private var isLoadingMoreParticipants = false
    private var videoRejoinTask: Task<Void, Never>?
    private var videoRejoinGeneration = UUID()
    private var screenSharingTask: Task<Void, Never>?
    private var screenSharingGeneration = UUID()
    private var muteUpdateTask: Task<Void, Never>?
    private var muteUpdateGeneration = UUID()
    private var pendingMutedValue: Bool?
    private var handUpdateTask: Task<Void, Never>?
    private var volumeUpdateTask: Task<Void, Never>?
    private var didReportConnected = false
    private var isMuted = false
    private var speakingCleanupTask: Task<Void, Never>?
    private var speakingLastActiveAt = [UInt32: TimeInterval]()
    private var messageExpirationTask: Task<Void, Never>?
    private var messageLifetime = 10
    private var centralVideoEndpointId: String?
    private var hasCentralVideo = false

    private static func enginePreferences(from configuration: JsonValue) -> EnginePreferences {
        guard case .jsonValueObject(let object) = configuration else { return EnginePreferences() }
        var preferences = EnginePreferences()
        for member in object.members {
            guard case .jsonValueNumber(let number) = member.value else { continue }
            switch member.key {
            case "voice_chat_send_bitrate":
                preferences.outgoingAudioBitrateKbit = Int32(clamping: Int(number.value))
            case "ios_calls_prioritize_vp8":
                preferences.prioritizeVP8 = number.value != 0
            case "ios_calls_group_reference_impl":
                preferences.useReferenceImpl = number.value != 0
            default:
                break
            }
        }
        return preferences
    }

    private static func broadcastScale(durationMilliseconds: Int64) -> Int? {
        switch durationMilliseconds {
        case 1000: 0
        case 500: 1
        case 250: 2
        case 125: 3
        default: nil
        }
    }

    private static func groupCallVideoQuality(
        from quality: TelegramGroupCallEngine.RequestedVideoQuality,
    ) -> GroupCallVideoQuality {
        switch quality {
        case .thumbnail: .groupCallVideoQualityThumbnail
        case .medium: .groupCallVideoQualityMedium
        case .full: .groupCallVideoQualityFull
        }
    }

    private func setHandRaised(_ isHandRaised: Bool) {
        guard case .connected = state,
              let groupCall,
              groupCall.isVideoChat,
              self.isHandRaised != isHandRaised,
              !isUpdatingHandRaised,
              let participantId = participants.values.first(where: \.isCurrentUser)?.participantId
        else { return }

        isUpdatingHandRaised = true
        handUpdateTask?.cancel()
        let generation = operationGeneration
        handUpdateTask = Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await service.toggleGroupCallParticipantIsHandRaised(
                    groupCallId: groupCall.id,
                    isHandRaised: isHandRaised,
                    participantId: participantId,
                )
                guard operationGeneration == generation, self.groupCall?.id == groupCall.id else { return }
                isUpdatingHandRaised = false
                handUpdateTask = nil
            } catch is CancellationError {
                return
            } catch {
                guard operationGeneration == generation, self.groupCall?.id == groupCall.id else { return }
                isUpdatingHandRaised = false
                handUpdateTask = nil
                log("[GroupCall] couldn't update raised hand to \(isHandRaised): \(error)")
            }
        }
    }

    private func begin(
        mode: Mode,
        isMuted: Bool,
        privateCallEngine: TelegramCallEngine?,
        audioSessionActive: Bool,
        prioritizeVP8: Bool,
    ) {
        guard case .idle = state else { return }
        let generation = beginNewOperation()
        let bridge = TelegramGroupCallEncryptionBridge(service: service)
        encryptionBridge = bridge
        state = .preparing
        self.isMuted = isMuted
        messageLifetime = 10
        messageCharacterLimit = 128

        enginePreparationTask = Task { [weak self, weak privateCallEngine] in
            guard let self else { return }
            var preferences = EnginePreferences()
            // A single application-config fetch feeds both the media-engine preferences and the
            // in-call message settings (TTL / character limit); the two used to fetch it separately.
            do {
                let configuration = try await service.getApplicationConfig()
                guard operationGeneration == generation else { return }
                preferences = Self.enginePreferences(from: configuration)
                applyMessageConfiguration(configuration)
            } catch is CancellationError {
                return
            } catch {
                guard operationGeneration == generation else { return }
                log("[GroupCall] couldn't load call configuration: \(error)")
            }
            guard operationGeneration == generation else { return }
            do {
                let messageLengthOption = try await service.getOption(
                    name: "group_call_message_text_length_max",
                )
                if operationGeneration == generation,
                   case .optionValueInteger(let value) = messageLengthOption
                {
                    messageCharacterLimit = max(1, Int(value.value.rawValue))
                }
            } catch is CancellationError {
                return
            } catch {
                guard operationGeneration == generation else { return }
                log("[GroupCall] couldn't load the group-call message length option: \(error)")
            }
            guard operationGeneration == generation else { return }
            expireMessagesAndScheduleNext()
            guard case .preparing = state else { return }
            prepareEngine(
                mode: mode,
                isMuted: isMuted,
                privateCallEngine: privateCallEngine,
                audioSessionActive: audioSessionActive,
                fallbackPrioritizeVP8: prioritizeVP8,
                preferences: preferences,
                generation: generation,
                bridge: bridge,
            )
            enginePreparationTask = nil
        }
    }

    private func prepareEngine(
        mode: Mode,
        isMuted: Bool,
        privateCallEngine: TelegramCallEngine?,
        audioSessionActive: Bool,
        fallbackPrioritizeVP8: Bool,
        preferences: EnginePreferences,
        generation: UUID,
        bridge: TelegramGroupCallEncryptionBridge,
    ) {
        let temporaryDirectory = FileManager.default.temporaryDirectory
        let logIdentifier = UUID().uuidString

        // A chat-bound video chat is server-mixed, not E2E: no frame encryption, plain group-call
        // transport. `.create` / `.join` (invite link or message) are always E2E conferences.
        let isVideoChat =
            if case .videoChat = mode {
                true
            } else {
                false
            }

        let configuration = TelegramGroupCallEngine.Configuration(
            encryption: isVideoChat ? nil : bridge.makeEncryption(),
            isConference: !isVideoChat,
            broadcast: isVideoChat ? makeBroadcastDataSource(generation: generation) : nil,
            isActiveByDefault: privateCallEngine == nil,
            isMuted: isMuted,
            outgoingAudioBitrateKbit: preferences.outgoingAudioBitrateKbit,
            prioritizeVP8: preferences.prioritizeVP8 || fallbackPrioritizeVP8,
            useReferenceImpl: preferences.useReferenceImpl,
            logPath: temporaryDirectory.appending(path: "SwiftTG-GroupCall-\(logIdentifier).log").path,
            statsLogPath: temporaryDirectory.appending(path: "SwiftTG-GroupCall-\(logIdentifier)-Stats.json").path,
        )
        let joinPayloadReady: @Sendable (String, Int) -> Void = { [weak self] payload, audioSourceId in
            Task { @MainActor [weak self] in
                self?.submitJoin(
                    mode: mode,
                    payload: payload,
                    audioSourceId: audioSourceId,
                    isMuted: isMuted,
                    generation: generation,
                    bridge: bridge,
                )
            }
        }
        let networkStateChanged: @Sendable (TelegramGroupCallEngine.NetworkState) -> Void = {
            [weak self] networkState in
            Task { @MainActor [weak self] in
                self?.handle(networkState, generation: generation)
            }
        }
        let signalBarsChanged: @Sendable (Int32) -> Void = { [weak self] signalBars in
            Task { @MainActor [weak self] in
                guard let self, operationGeneration == generation else { return }
                let value = min(4, max(0, Int(signalBars)))
                self.signalBars = value
                onSignalBarsChanged?(value)
            }
        }
        let audioLevelsChanged: @Sendable ([TelegramGroupCallEngine.AudioLevel]) -> Void = { [weak self] levels in
            Task { @MainActor [weak self] in
                guard let self, operationGeneration == generation else { return }
                handleAudioLevels(levels, generation: generation)
            }
        }

        if let privateCallEngine {
            privateCallEngine.prepareGroupCall(
                engine: engine,
                configuration: configuration,
                audioSessionActive: audioSessionActive,
                joinPayloadReady: joinPayloadReady,
                networkStateChanged: networkStateChanged,
                audioLevelsChanged: audioLevelsChanged,
                signalBarsChanged: signalBarsChanged,
            )
        } else {
            engine.prepareJoin(
                configuration: configuration,
                sharedAudioDevice: nil,
                audioSessionActive: audioSessionActive,
                joinPayloadReady: joinPayloadReady,
                networkStateChanged: networkStateChanged,
                audioLevelsChanged: audioLevelsChanged,
                signalBarsChanged: signalBarsChanged,
            )
        }
    }

    /// Fetches broadcast/HLS stream segments through TDLib so tgcalls can play a video chat or live
    /// stream while its connection is in broadcast mode (see `applyJoinResponse`).
    private func makeBroadcastDataSource(generation: UUID) -> TelegramGroupCallEngine.BroadcastDataSource {
        TelegramGroupCallEngine.BroadcastDataSource(
            currentTimeMilliseconds: { [weak self] in
                await self?.broadcastCurrentTimeMilliseconds(generation: generation)
                    ?? Int64(Foundation.Date().timeIntervalSince1970 * 1000)
            },
            audioPart: { [weak self] timestamp, duration in
                await self?.broadcastStreamSegment(
                    timestampMilliseconds: timestamp,
                    durationMilliseconds: duration,
                    channelId: 0,
                    videoQuality: nil,
                    generation: generation,
                )
            },
            videoPart: { [weak self] timestamp, duration, channelId, quality in
                await self?.broadcastStreamSegment(
                    timestampMilliseconds: timestamp,
                    durationMilliseconds: duration,
                    channelId: Int(channelId),
                    videoQuality: quality,
                    generation: generation,
                )
            },
        )
    }

    @MainActor private func broadcastCurrentTimeMilliseconds(generation: UUID) async -> Int64 {
        let wallClock = Int64(Foundation.Date().timeIntervalSince1970 * 1000)
        guard operationGeneration == generation, let groupCall, groupCall.isRtmpStream else {
            return wallClock
        }
        guard let stream = try? await service.getGroupCallStreams(groupCallId: groupCall.id).streams.first
        else { return 0 }
        return Int64(stream.timeOffset)
    }

    @MainActor private func broadcastStreamSegment(
        timestampMilliseconds: Int64,
        durationMilliseconds: Int64,
        channelId: Int,
        videoQuality: TelegramGroupCallEngine.RequestedVideoQuality?,
        generation: UUID,
    ) async -> TelegramGroupCallEngine.BroadcastPart? {
        guard operationGeneration == generation,
              let groupCallId = groupCall?.id,
              let scale = Self.broadcastScale(durationMilliseconds: durationMilliseconds)
        else { return nil }
        do {
            let segment = try await service.getGroupCallStreamSegment(
                channelId: channelId,
                groupCallId: groupCallId,
                scale: scale,
                timeOffset: timestampMilliseconds,
                videoQuality: videoQuality.map(Self.groupCallVideoQuality(from:)),
            )
            guard !segment.data.isEmpty else { return nil }
            return TelegramGroupCallEngine.BroadcastPart(
                timestampMilliseconds: timestampMilliseconds,
                responseTimeSeconds: Foundation.Date().timeIntervalSince1970,
                oggData: segment.data,
            )
        } catch {
            return nil
        }
    }

    private func submitJoin(
        mode: Mode,
        payload: String,
        audioSourceId: Int,
        isMuted: Bool,
        generation: UUID,
        bridge: TelegramGroupCallEncryptionBridge,
    ) {
        guard operationGeneration == generation, case .preparing = state else { return }
        operationTask?.cancel()
        operationTask = Task { [weak self] in
            guard let self else { return }
            let parameters = GroupCallJoinParameters(
                audioSourceId: audioSourceId,
                isMuted: isMuted,
                isMyVideoEnabled: false,
                payload: payload,
            )

            do {
                let joinedGroupCallId: Int
                let joinPayload: String
                switch mode {
                case .create:
                    let info = try await service.createGroupCall(joinParameters: parameters)
                    joinedGroupCallId = info.groupCallId
                    joinPayload = info.joinPayload
                case .join(let inputGroupCall):
                    let info = try await service.joinGroupCall(
                        inputGroupCall: inputGroupCall,
                        joinParameters: parameters,
                    )
                    joinedGroupCallId = info.groupCallId
                    joinPayload = info.joinPayload
                case .videoChat(let groupCallId, let inviteHash, let participantId):
                    let response = try await service.joinVideoChat(
                        groupCallId: groupCallId,
                        inviteHash: inviteHash,
                        joinParameters: parameters,
                        participantId: participantId,
                    )
                    joinedGroupCallId = groupCallId
                    joinPayload = response.text
                }

                guard operationGeneration == generation else {
                    _ =
                        switch mode {
                        case .create:
                            try? await service.endGroupCall(groupCallId: joinedGroupCallId)
                        case .join, .videoChat:
                            try? await service.leaveGroupCall(groupCallId: joinedGroupCallId)
                        }
                    return
                }

                // The E2E encryption bridge is unused for a video chat (server-mixed, not E2E).
                if case .videoChat = mode {} else {
                    bridge.setGroupCallId(joinedGroupCallId)
                }
                let call = try await service.getGroupCall(groupCallId: joinedGroupCallId)
                guard operationGeneration == generation else {
                    _ =
                        if call.isOwned {
                            try? await service.endGroupCall(groupCallId: joinedGroupCallId)
                        } else {
                            try? await service.leaveGroupCall(groupCallId: joinedGroupCallId)
                        }
                    return
                }

                groupCall = call
                currentJoinMode =
                    switch mode {
                    case .create:
                        .join(.inputGroupCallLink(.init(link: call.inviteLink)))
                    case .join, .videoChat:
                        mode
                    }
                state = .connecting(groupCallId: call.id, inviteLink: call.inviteLink)
                engine.applyJoinResponse(joinPayload)
                loadMoreParticipants()
                guard operationGeneration == generation else { return }
                onPrepared?(PreparedCall(groupCallId: call.id, inviteLink: call.inviteLink))
            } catch {
                guard operationGeneration == generation else { return }
                log("[GroupCall] failed to prepare call: \(error)")
                reset(to: .failed)
            }
        }
    }

    private func handle(_ networkState: TelegramGroupCallEngine.NetworkState, generation: UUID) {
        guard operationGeneration == generation, let groupCall else { return }
        if networkState.isConnected {
            state = .connected(groupCallId: groupCall.id, inviteLink: groupCall.inviteLink)
            if !didReportConnected {
                didReportConnected = true
                onConnected?()
            }
        } else {
            state = .connecting(groupCallId: groupCall.id, inviteLink: groupCall.inviteLink)
        }
    }

    private func requestRejoin() {
        guard rejoinTask == nil,
              !isRequestingRejoinPayload,
              let groupCall,
              let joinMode = currentJoinMode
        else { return }

        let generation = operationGeneration
        let groupCallId = groupCall.id
        let requestGeneration = UUID()
        rejoinGeneration = requestGeneration
        isRequestingRejoinPayload = true
        state = .connecting(groupCallId: groupCall.id, inviteLink: groupCall.inviteLink)
        log("[GroupCall] rejoin requested for groupCallId=\(groupCallId)")
        engine.emitJoinPayload { [weak self] payload, audioSourceId in
            Task { @MainActor [weak self] in
                self?.submitRejoin(
                    mode: joinMode,
                    payload: payload,
                    audioSourceId: audioSourceId,
                    groupCallId: groupCallId,
                    generation: generation,
                    requestGeneration: requestGeneration,
                )
            }
        }
    }

    private func submitRejoin(
        mode: Mode,
        payload: String,
        audioSourceId: Int,
        groupCallId: Int,
        generation: UUID,
        requestGeneration: UUID,
    ) {
        guard operationGeneration == generation,
              rejoinGeneration == requestGeneration,
              rejoinTask == nil,
              groupCall?.id == groupCallId
        else { return }
        isRequestingRejoinPayload = false

        rejoinTask = Task { [weak self] in
            guard let self else { return }
            let parameters = GroupCallJoinParameters(
                audioSourceId: audioSourceId,
                isMuted: isMuted,
                isMyVideoEnabled: isLocalVideoEnabled,
                payload: payload,
            )
            do {
                let joinPayload: String
                switch mode {
                case .join(let inputGroupCall):
                    let info = try await service.joinGroupCall(
                        inputGroupCall: inputGroupCall,
                        joinParameters: parameters,
                    )
                    joinPayload = info.joinPayload
                case .videoChat(let groupCallId, let inviteHash, let participantId):
                    let response = try await service.joinVideoChat(
                        groupCallId: groupCallId,
                        inviteHash: inviteHash,
                        joinParameters: parameters,
                        participantId: participantId,
                    )
                    joinPayload = response.text
                case .create:
                    return
                }
                guard operationGeneration == generation,
                      rejoinGeneration == requestGeneration,
                      groupCall?.id == groupCallId
                else { return }
                engine.applyJoinResponse(joinPayload)
                let refreshedCall = try await service.getGroupCall(groupCallId: groupCallId)
                guard operationGeneration == generation,
                      rejoinGeneration == requestGeneration,
                      groupCall?.id == groupCallId
                else { return }
                groupCall = refreshedCall
                log("[GroupCall] rejoined groupCallId=\(groupCallId)")
            } catch is CancellationError {
                return
            } catch {
                guard operationGeneration == generation,
                      rejoinGeneration == requestGeneration
                else { return }
                log("[GroupCall] rejoin failed for groupCallId=\(groupCallId): \(error)")
                rejoinTask = nil
                scheduleRejoinRetry(generation: generation, groupCallId: groupCallId)
                return
            }
            guard operationGeneration == generation,
                  rejoinGeneration == requestGeneration
            else { return }
            rejoinTask = nil
        }
    }

    private func scheduleRejoinRetry(generation: UUID, groupCallId: Int) {
        rejoinRetryTask?.cancel()
        rejoinRetryTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(2))
            } catch {
                return
            }
            guard let self,
                  operationGeneration == generation,
                  groupCall?.id == groupCallId,
                  groupCall?.needRejoin == true
            else { return }
            rejoinRetryTask = nil
            requestRejoin()
        }
    }

    private func submitVideoRejoin(
        payload: String,
        audioSourceId: Int,
        isVideoEnabled: Bool,
        generation: UUID,
    ) {
        guard operationGeneration == generation,
              let groupCall,
              !groupCall.inviteLink.isEmpty,
              case .connected = state
        else { return }

        videoRejoinTask?.cancel()
        let rejoinGeneration = UUID()
        videoRejoinGeneration = rejoinGeneration
        let groupCallId = groupCall.id
        let inviteLink = groupCall.inviteLink
        videoRejoinTask = Task { [weak self] in
            guard let self else { return }
            let parameters = GroupCallJoinParameters(
                audioSourceId: audioSourceId,
                isMuted: isMuted,
                isMyVideoEnabled: isVideoEnabled,
                payload: payload,
            )
            do {
                let info = try await service.joinGroupCall(
                    inputGroupCall: .inputGroupCallLink(.init(link: inviteLink)),
                    joinParameters: parameters,
                )
                guard operationGeneration == generation,
                      videoRejoinGeneration == rejoinGeneration,
                      self.groupCall?.id == groupCallId
                else { return }
                engine.applyJoinResponse(info.joinPayload)
                isLocalVideoEnabled = isVideoEnabled
                log("[GroupCall] local video rejoined enabled=\(isVideoEnabled)")
            } catch is CancellationError {
                return
            } catch {
                guard operationGeneration == generation,
                      videoRejoinGeneration == rejoinGeneration
                else { return }
                log("[GroupCall] local video rejoin failed enabled=\(isVideoEnabled): \(error)")
                onLocalVideoFailed?()
            }
            guard operationGeneration == generation,
                  videoRejoinGeneration == rejoinGeneration
            else { return }
            videoRejoinTask = nil
        }
    }

    private func submitScreenSharingJoin(
        payload: String,
        audioSourceId: Int,
        generation: UUID,
        screenSharingGeneration: UUID,
    ) {
        guard operationGeneration == generation,
              self.screenSharingGeneration == screenSharingGeneration,
              let groupCall
        else { return }
        let groupCallId = groupCall.id
        screenSharingTask = Task { [weak self] in
            guard let self else { return }
            do {
                let response = try await service.startGroupCallScreenSharing(
                    audioSourceId: audioSourceId,
                    groupCallId: groupCallId,
                    payload: payload,
                )
                guard operationGeneration == generation,
                      self.screenSharingGeneration == screenSharingGeneration,
                      self.groupCall?.id == groupCallId
                else { return }
                screencastEngine.applyJoinResponse(response.text)
                isScreenSharing = true
                log("[GroupCall] screen sharing started for groupCallId=\(groupCallId)")
            } catch is CancellationError {
                return
            } catch {
                guard operationGeneration == generation,
                      self.screenSharingGeneration == screenSharingGeneration
                else { return }
                screencastEngine.stop()
                isScreenSharing = false
                log("[GroupCall] screen sharing failed for groupCallId=\(groupCallId): \(error)")
                onScreenSharingFailed?()
            }
            guard operationGeneration == generation,
                  self.screenSharingGeneration == screenSharingGeneration
            else { return }
            screenSharingTask = nil
        }
    }

    private func handle(_ update: Update) {
        switch update {
        case .updateGroupCall(let value):
            guard value.groupCall.id == groupCall?.id else { return }
            groupCall = value.groupCall
            if !value.groupCall.isActive {
                reset(to: .ended)
            } else if value.groupCall.needRejoin {
                requestRejoin()
            }
        case .updateGroupCallParticipant(let value):
            guard value.groupCallId == groupCall?.id else { return }
            let previousParticipant = participants[value.participant.participantId]
            if value.participant.order.isEmpty {
                participants.removeValue(forKey: value.participant.participantId)
                onParticipantChanged?(previousParticipant, nil)
            } else {
                participants[value.participant.participantId] = value.participant
                if value.participant.isCurrentUser {
                    handleLocalMuteUpdate(value.participant)
                }
                onParticipantChanged?(previousParticipant, value.participant)
            }
            refreshMediaChannels()
        case .updateGroupCallVerificationState(let value):
            guard value.groupCallId == groupCall?.id else { return }
            verificationEmojis = value.emojis
        case .updateNewGroupCallMessage(let value):
            guard value.groupCallId == groupCall?.id else { return }
            messages[value.message.messageId] = value.message
            expireMessagesAndScheduleNext()
        case .updateGroupCallMessageSendFailed(let value):
            guard value.groupCallId == groupCall?.id else { return }
            log("[GroupCall] messageId=\(value.messageId) failed to send: \(value.error)")
        case .updateGroupCallMessagesDeleted(let value):
            guard value.groupCallId == groupCall?.id else { return }
            for messageId in value.messageIds {
                messages.removeValue(forKey: messageId)
            }
            expireMessagesAndScheduleNext()
        default:
            break
        }
    }

    private func refreshMediaChannels() {
        var channels = [TelegramGroupCallEngine.MediaChannel]()
        var videoChannels = [TelegramGroupCallEngine.VideoChannel]()
        for participant in participants.values {
            let peerId: Int64 =
                switch participant.participantId {
                case .messageSenderUser(let user):
                    user.userId
                case .messageSenderChat(let chat):
                    chat.chatId
                }
            if participant.audioSourceId != 0 {
                channels.append(.init(
                    audioSourceId: UInt32(bitPattern: Int32(truncatingIfNeeded: participant.audioSourceId)),
                    peerId: peerId,
                ))
            }
            if participant.screenSharingAudioSourceId != 0 {
                channels.append(.init(
                    audioSourceId: UInt32(
                        bitPattern: Int32(truncatingIfNeeded: participant.screenSharingAudioSourceId),
                    ),
                    peerId: peerId,
                ))
            }
            guard !participant.isCurrentUser, participant.audioSourceId != 0 else { continue }
            if let videoInfo = participant.videoInfo {
                videoChannels.append(videoChannel(
                    participant: participant,
                    peerId: peerId,
                    videoInfo: videoInfo,
                    isScreenSharing: false,
                ))
            }
            if let screenSharingVideoInfo = participant.screenSharingVideoInfo {
                videoChannels.append(videoChannel(
                    participant: participant,
                    peerId: peerId,
                    videoInfo: screenSharingVideoInfo,
                    isScreenSharing: true,
                ))
            }
        }
        engine.updateMediaChannels(channels)
        engine.updateRequestedVideoChannels(
            videoChannels,
            maximumQuality: incomingVideoQuality,
            centralEndpointId: centralVideoEndpointId,
            hasCentralVideo: hasCentralVideo,
        )
        for participant in participants.values where !participant.isCurrentUser {
            setParticipantVolume(
                participant,
                mutedForCurrentUser: participant.isMutedForCurrentUser,
            )
        }
    }

    private func setParticipantVolume(
        _ participant: GroupCallParticipant,
        mutedForCurrentUser: Bool,
    ) {
        applyParticipantVolume(
            participant,
            volumeLevel: mutedForCurrentUser ? 0 : participant.volumeLevel,
        )
    }

    private func applyParticipantVolume(
        _ participant: GroupCallParticipant,
        volumeLevel: Int,
    ) {
        let volume = min(2, max(0, Double(volumeLevel) / 10000))
        if participant.audioSourceId != 0 {
            engine.setVolume(
                audioSourceId: UInt32(bitPattern: Int32(truncatingIfNeeded: participant.audioSourceId)),
                volume: volume,
            )
        }
        if participant.screenSharingAudioSourceId != 0 {
            engine.setVolume(
                audioSourceId: UInt32(
                    bitPattern: Int32(truncatingIfNeeded: participant.screenSharingAudioSourceId),
                ),
                volume: volume,
            )
        }
    }

    private func handleLocalMuteUpdate(_ participant: GroupCallParticipant) {
        canUnmuteSelf = participant.canUnmuteSelf
        let serverMuted = participant.isMutedForAllUsers
        if let pendingMutedValue {
            if pendingMutedValue == serverMuted {
                self.pendingMutedValue = nil
            } else {
                return
            }
        }
        guard isMuted != serverMuted else { return }
        isMuted = serverMuted
        engine.setMuted(serverMuted)
        onLocalMuteStateChanged?(serverMuted)
    }

    private func videoChannel(
        participant: GroupCallParticipant,
        peerId: Int64,
        videoInfo: GroupCallParticipantVideoInfo,
        isScreenSharing: Bool,
    ) -> TelegramGroupCallEngine.VideoChannel {
        TelegramGroupCallEngine.VideoChannel(
            audioSourceId: UInt32(bitPattern: Int32(truncatingIfNeeded: participant.audioSourceId)),
            peerId: peerId,
            endpointId: videoInfo.endpointId,
            sourceGroups: videoInfo.sourceGroups.map { group in
                TelegramGroupCallEngine.VideoChannel.SourceGroup(
                    semantics: group.semantics,
                    sourceIds: group.sourceIds.map {
                        UInt32(bitPattern: Int32(truncatingIfNeeded: $0))
                    },
                )
            },
            isScreenSharing: isScreenSharing,
        )
    }

    private func handleAudioLevels(
        _ levels: [TelegramGroupCallEngine.AudioLevel],
        generation: UUID,
    ) {
        let timestamp = Foundation.Date.timeIntervalSinceReferenceDate
        for level in levels where level.level > 0.1 && level.hasVoice {
            speakingLastActiveAt[level.audioSourceId] = timestamp
        }
        speakingAudioSourceIds = Set(speakingLastActiveAt.keys)
        guard speakingCleanupTask == nil, !speakingLastActiveAt.isEmpty else { return }
        speakingCleanupTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .milliseconds(500))
                } catch {
                    return
                }
                guard let self, operationGeneration == generation else { return }
                let cutoff = Foundation.Date.timeIntervalSinceReferenceDate - 2
                speakingLastActiveAt = speakingLastActiveAt.filter { $0.value > cutoff }
                speakingAudioSourceIds = Set(speakingLastActiveAt.keys)
                if speakingLastActiveAt.isEmpty {
                    speakingCleanupTask = nil
                    return
                }
            }
        }
    }

    private func applyMessageConfiguration(_ configuration: JsonValue) {
        guard case .jsonValueObject(let object) = configuration else { return }
        for member in object.members {
            guard case .jsonValueNumber(let number) = member.value else { continue }
            switch member.key {
            case "group_call_message_ttl":
                messageLifetime = max(0, Int(number.value))
            default:
                break
            }
        }
    }

    private func expireMessagesAndScheduleNext() {
        messageExpirationTask?.cancel()
        messageExpirationTask = nil
        let currentTimestamp = Int(Foundation.Date().timeIntervalSince1970)
        let expiredMessageIds = messages.values.compactMap { message -> Int? in
            message.date + messageLifetime < currentTimestamp ? message.messageId : nil
        }
        for messageId in expiredMessageIds {
            messages.removeValue(forKey: messageId)
        }
        guard let nextExpirationTimestamp = messages.values
            .map({ $0.date + messageLifetime })
            .min()
        else { return }

        let generation = operationGeneration
        let delaySeconds = max(1, nextExpirationTimestamp - currentTimestamp + 1)
        messageExpirationTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(delaySeconds))
            } catch {
                return
            }
            guard let self, operationGeneration == generation else { return }
            expireMessagesAndScheduleNext()
        }
    }

    @discardableResult private func beginNewOperation() -> UUID {
        operationTask?.cancel()
        operationTask = nil
        enginePreparationTask?.cancel()
        enginePreparationTask = nil
        rejoinTask?.cancel()
        rejoinTask = nil
        rejoinRetryTask?.cancel()
        rejoinRetryTask = nil
        rejoinGeneration = UUID()
        isRequestingRejoinPayload = false
        participantLoadingTask?.cancel()
        participantLoadingTask = nil
        isLoadingMoreParticipants = false
        videoRejoinTask?.cancel()
        videoRejoinTask = nil
        videoRejoinGeneration = UUID()
        screenSharingTask?.cancel()
        screenSharingTask = nil
        screenSharingGeneration = UUID()
        screencastEngine.stop()
        muteUpdateTask?.cancel()
        muteUpdateTask = nil
        muteUpdateGeneration = UUID()
        pendingMutedValue = nil
        handUpdateTask?.cancel()
        handUpdateTask = nil
        isUpdatingHandRaised = false
        volumeUpdateTask?.cancel()
        volumeUpdateTask = nil
        messageExpirationTask?.cancel()
        messageExpirationTask = nil
        operationGeneration = UUID()
        return operationGeneration
    }

    private func reset(to state: State) {
        // Invalidate every in-flight operation before tearing state down. `leave()`/`cancel()`
        // already do this, but `reset` is also reached directly from `handle(_:)` when a server
        // update ends the call - without this, a rejoin/join/video/mute continuation could resume
        // afterwards, pass its now-stale `operationGeneration` check (which `reset` alone never
        // bumped) and resurrect `groupCall`/`participants` after the call is gone.
        beginNewOperation()
        engine.stop()
        speakingCleanupTask?.cancel()
        speakingCleanupTask = nil
        speakingLastActiveAt.removeAll(keepingCapacity: false)
        speakingAudioSourceIds.removeAll(keepingCapacity: false)
        encryptionBridge = nil
        currentJoinMode = nil
        groupCall = nil
        participants.removeAll(keepingCapacity: false)
        messages.removeAll(keepingCapacity: false)
        messageLifetime = 10
        messageCharacterLimit = 128
        verificationEmojis = []
        signalBars = nil
        didReportConnected = false
        isLocalVideoEnabled = false
        isScreenSharing = false
        canUnmuteSelf = true
        isUpdatingHandRaised = false
        incomingVideoQuality = .p720
        centralVideoEndpointId = nil
        hasCentralVideo = false
        isMuted = false
        self.state = state
        if case .ended = state {
            onEnded?()
        } else if case .failed = state {
            onFailed?()
        }
    }
}
