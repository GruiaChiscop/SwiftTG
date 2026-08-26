// TelegramGroupCallCoordinator.swift

import Combine
import Foundation
import Observation
import TDLibKit
@preconcurrency import TgVoipWebrtc

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
    private(set) var verificationEmojis = [String]()
    private(set) var signalBars: Int?

    var onPrepared: ((PreparedCall) -> Void)?
    var onConnected: (() -> Void)?
    var onSignalBarsChanged: ((Int) -> Void)?
    var onFailed: (() -> Void)?
    var onEnded: (() -> Void)?

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
        begin(
            mode: .join(inviteLink: inviteLink),
            isMuted: isMuted,
            privateCallEngine: privateCallEngine,
            audioSessionActive: audioSessionActive,
            prioritizeVP8: prioritizeVP8,
        )
    }

    func invite(userId: Int64, isVideo: Bool) async throws -> InviteGroupCallParticipantResult {
        guard let groupCallId = groupCall?.id else {
            throw CoordinatorError.notReady
        }
        return try await service.inviteGroupCallParticipant(
            groupCallId: groupCallId,
            isVideo: isVideo,
            userId: userId,
        )
    }

    func setMuted(_ muted: Bool) {
        engine.setMuted(muted)
    }

    func setAudioSessionActive(_ active: Bool) {
        engine.setAudioSessionActive(active)
    }

    func activateIncomingAudio() {
        engine.activateIncomingAudio()
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
        _ = beginNewOperation()
        reset(to: .idle)
    }

    // MARK: Private

    private enum Mode: Sendable {
        case create
        case join(inviteLink: String)
    }

    private enum CoordinatorError: Swift.Error {
        case notReady
    }

    private let service: any TelegramService
    private let engine = TelegramGroupCallEngine()
    private var encryptionBridge: TelegramGroupCallEncryptionBridge?
    private var cancellables = Set<AnyCancellable>()
    private var operationTask: Task<Void, Never>?
    private var operationGeneration = UUID()
    private var didReportConnected = false

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

        let configuration = TelegramGroupCallEngine.Configuration(
            encryption: bridge.makeEncryption(),
            isActiveByDefault: privateCallEngine == nil,
            isMuted: isMuted,
            prioritizeVP8: prioritizeVP8,
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

        if let privateCallEngine {
            privateCallEngine.prepareGroupCall(
                engine: engine,
                configuration: configuration,
                audioSessionActive: audioSessionActive,
                joinPayloadReady: joinPayloadReady,
                networkStateChanged: networkStateChanged,
                signalBarsChanged: signalBarsChanged,
            )
        } else {
            engine.prepareJoin(
                configuration: configuration,
                sharedAudioDevice: nil,
                audioSessionActive: audioSessionActive,
                joinPayloadReady: joinPayloadReady,
                networkStateChanged: networkStateChanged,
                signalBarsChanged: signalBarsChanged,
            )
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
                let info: GroupCallInfo =
                    switch mode {
                    case .create:
                        try await service.createGroupCall(joinParameters: parameters)
                    case .join(let inviteLink):
                        try await service.joinGroupCall(
                            inputGroupCall: .inputGroupCallLink(.init(link: inviteLink)),
                            joinParameters: parameters,
                        )
                    }

                guard operationGeneration == generation else {
                    _ =
                        if case .create = mode {
                            try? await service.endGroupCall(groupCallId: info.groupCallId)
                        } else {
                            try? await service.leaveGroupCall(groupCallId: info.groupCallId)
                        }
                    return
                }

                bridge.setGroupCallId(info.groupCallId)
                let call = try await service.getGroupCall(groupCallId: info.groupCallId)
                guard operationGeneration == generation else {
                    _ =
                        if call.isOwned {
                            try? await service.endGroupCall(groupCallId: info.groupCallId)
                        } else {
                            try? await service.leaveGroupCall(groupCallId: info.groupCallId)
                        }
                    return
                }

                groupCall = call
                state = .connecting(groupCallId: call.id, inviteLink: call.inviteLink)
                engine.applyJoinResponse(info.joinPayload)
                _ = try? await service.loadGroupCallParticipants(groupCallId: call.id, limit: 100)
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

    private func handle(_ update: Update) {
        switch update {
        case .updateGroupCall(let value):
            guard value.groupCall.id == groupCall?.id else { return }
            groupCall = value.groupCall
            if !value.groupCall.isActive {
                reset(to: .ended)
            }
        case .updateGroupCallParticipant(let value):
            guard value.groupCallId == groupCall?.id else { return }
            if value.participant.order.isEmpty {
                participants.removeValue(forKey: value.participant.participantId)
            } else {
                participants[value.participant.participantId] = value.participant
            }
            refreshMediaChannels()
        case .updateGroupCallVerificationState(let value):
            guard value.groupCallId == groupCall?.id else { return }
            verificationEmojis = value.emojis
        default:
            break
        }
    }

    private func refreshMediaChannels() {
        var channels = [TelegramGroupCallEngine.MediaChannel]()
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
        }
        engine.updateMediaChannels(channels)
    }

    @discardableResult private func beginNewOperation() -> UUID {
        operationTask?.cancel()
        operationTask = nil
        operationGeneration = UUID()
        return operationGeneration
    }

    private func reset(to state: State) {
        engine.stop()
        encryptionBridge = nil
        groupCall = nil
        participants.removeAll(keepingCapacity: false)
        verificationEmojis = []
        signalBars = nil
        didReportConnected = false
        self.state = state
        if case .ended = state {
            onEnded?()
        } else if case .failed = state {
            onFailed?()
        }
    }
}
