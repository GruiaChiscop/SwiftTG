// CallKitManager.swift

import AVFoundation
import CallKit
import Combine
import Foundation
import TDLibKit

// MARK: - CallKitManager

/// Reports call lifecycle events to the system (lock-screen call UI, Control Center, CarPlay,
/// Watch) via `CXProvider`, and relays the resulting actions (answer/end/mute, or a call started
/// from CallKit's own UI) into `TelegramCallSession`. Apple requires every VoIP call - incoming or
/// outgoing - to go through this, not just calls that arrive via a VoIP push.
@MainActor final class CallKitManager: NSObject {
    // MARK: Lifecycle

    override private init() {
        let configuration = CXProviderConfiguration()
        configuration.supportsVideo = false
        configuration.maximumCallGroups = 1
        configuration.maximumCallsPerCallGroup = 1
        configuration.supportedHandleTypes = [.generic]
        self.provider = CXProvider(configuration: configuration)
        super.init()
        provider.setDelegate(self, queue: nil)
    }

    // MARK: Internal

    static let shared = CallKitManager()

    /// Whether CallKit has actually handed control of the shared `AVAudioSession` to the app, fed
    /// only by `provider(_:didActivate:)`/`didDeactivate:` below. `TelegramCallSession` must drive
    /// its audio device's activation off this - never activate independently. This is the exact
    /// pattern Telegram-iOS itself uses (`CallKitIntegration.audioSessionActive`, a Signal fed the
    /// same way and subscribed to by `OngoingCallContext`/`SharedCallAudioContext` before they ever
    /// touch the audio device) - CallKit owns exclusive control of the session, and activating
    /// independently of its handoff can silently produce no audio route even though the engine
    /// itself thinks it's active.
    var audioSessionActivePublisher: AnyPublisher<Bool, Never> { audioSessionActiveSubject.eraseToAnyPublisher() }

    /// Wires `TelegramCallSession`'s lifecycle hooks - call once at app launch, before any call can
    /// arrive.
    func start() {
        let session = TelegramCallSession.shared
        session.onIncomingCall = { [weak self] call in self?.reportIncoming(call) }
        session.onCallConnected = { [weak self] in self?.reportConnected() }
        session.onCallEnded = { [weak self] in self?.reportEnded() }
    }

    /// Routes an outgoing call through CallKit's own `CXStartCallAction` first, matching Apple's
    /// required flow, rather than calling `TelegramCallSession.startCall` directly - the actual
    /// `createCall` only happens once CallKit grants the action in
    /// `provider(_:perform: CXStartCallAction)` below.
    func startOutgoingCall(userId: Int64, displayName: String) {
        guard currentCallUUID == nil, !isRequestingOutgoingCall else {
            log("[CallKit] refusing a second outgoing call while another call is active")
            return
        }
        isRequestingOutgoingCall = true
        Task { [weak self] in
            guard let self else { return }
            let granted = await AVAudioApplication.requestRecordPermission()
            guard granted else {
                isRequestingOutgoingCall = false
                log("[CallKit] microphone permission denied; outgoing call not started")
                return
            }

            TelegramCallSession.prepareAudioSession()
            let uuid = UUID()
            currentCallUUID = uuid
            currentUserId = userId
            isCurrentCallOutgoing = true
            isRequestingOutgoingCall = false

            let name = displayName.isEmpty ? "Telegram" : displayName
            let action = CXStartCallAction(call: uuid, handle: CXHandle(type: .generic, value: name))
            action.isVideo = false
            do {
                try await callController.request(CXTransaction(action: action))
            } catch {
                log("CallKit start request failed: \(error)")
                clearCurrentCall(ifMatching: uuid)
            }
        }
    }

    /// App-initiated hangups must travel through CallKit too. This keeps the system call UI and
    /// TDLib lifecycle on the same transaction, matching Telegram-iOS's `endCall(uuid:)` flow.
    func requestEndCall() {
        guard let uuid = currentCallUUID else {
            TelegramCallSession.shared.endFromSystem()
            return
        }
        guard !isRequestingEndCall, !isEndingLocally else { return }
        isRequestingEndCall = true
        Task {
            do {
                try await callController.request(CXTransaction(action: CXEndCallAction(call: uuid)))
            } catch {
                isRequestingEndCall = false
                log("CallKit end request failed: \(error)")
            }
        }
    }

    /// Reports a placeholder incoming call immediately, before TDLib has told us who it's from -
    /// PushKit requires a `CXProvider` report within a very tight window of every VoIP push, well
    /// before there's time to fetch the caller's name. `reportIncoming(_:)` below reconciles this
    /// placeholder with the real call once TDLib's own `updateCall` arrives shortly after, instead
    /// of reporting a second, duplicate call.
    @discardableResult func reportIncomingPlaceholder(callUniqueId: Int64?) -> Bool {
        pruneRecentlyEndedCalls()
        if let callUniqueId, recentlyEndedCallUniqueIds[callUniqueId] != nil {
            // The live TDLib update can beat its VoIP push. That call has already been reported to
            // and ended in CallKit, so reporting the late push creates a second ghost call.
            log("[CallKit] ignoring late placeholder for ended call uniqueId=\(callUniqueId)")
            return false
        }
        guard currentCallUUID == nil else {
            log(
                "[CallKit] reportIncomingPlaceholder skipped, already have currentCallUUID=\(currentCallUUID?.uuidString ?? "nil")",
            )
            return false
        }
        let uuid = UUID()
        TelegramCallSession.prepareAudioSession()
        currentCallUUID = uuid
        currentTelegramCallUniqueId = callUniqueId
        isCurrentCallOutgoing = false
        log("[CallKit] reportIncomingPlaceholder uuid=\(uuid)")
        provider.reportNewIncomingCall(with: uuid, update: Self.update(displayName: nil)) { [weak self] error in
            Task { @MainActor [weak self] in
                if let error {
                    log("[CallKit] failed to report placeholder incoming call: \(error)")
                    self?.clearCurrentCall(ifMatching: uuid)
                    TelegramCallSession.shared.cancelPendingSystemAction()
                } else {
                    log("[CallKit] placeholder reported successfully uuid=\(uuid)")
                }
            }
        }
        return true
    }

    /// Ends a placeholder reported by `reportIncomingPlaceholder()` if TDLib never actually
    /// produced a matching call (e.g. the caller hung up before the push finished processing) -
    /// without this, that placeholder would ring forever.
    func endPlaceholderIfStillPending() {
        guard let uuid = currentCallUUID, currentUserId == nil else {
            log(
                "[CallKit] endPlaceholderIfStillPending no-op, currentCallUUID=\(currentCallUUID?.uuidString ?? "nil") currentUserId=\(currentUserId.map(String.init) ?? "nil")",
            )
            return
        }
        log("[CallKit] endPlaceholderIfStillPending dropping unreconciled placeholder uuid=\(uuid)")
        // Matches Telegram-iOS's own CallKitIntegration.dropCall, which always reports
        // `.remoteEnded` (never `.failed`) when dropping an unreconciled placeholder.
        provider.reportCall(with: uuid, endedAt: nil, reason: .remoteEnded)
        TelegramCallSession.shared.cancelPendingSystemAction()
        clearCurrentCall(ifMatching: uuid)
    }

    // MARK: Private

    private let provider: CXProvider
    private let callController = CXCallController()
    private let audioSessionActiveSubject = CurrentValueSubject<Bool, Never>(false)
    private var currentCallUUID: UUID?
    private var currentUserId: Int64?
    private var currentTelegramCallUniqueId: Int64?
    private var recentlyEndedCallUniqueIds = [Int64: Foundation.Date]()
    private var isCurrentCallOutgoing = false
    private var isEndingLocally = false
    private var isRequestingEndCall = false
    private var isRequestingOutgoingCall = false

    private static func update(displayName: String?) -> CXCallUpdate {
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: displayName ?? "Telegram")
        update.localizedCallerName = displayName
        update.hasVideo = false
        update.supportsHolding = false
        update.supportsGrouping = false
        update.supportsUngrouping = false
        update.supportsDTMF = false
        return update
    }

    private func reportIncoming(_ call: Call) {
        let uuid: UUID
        if let existing = currentCallUUID {
            uuid = existing
            log(
                "[CallKit] reportIncoming reconciling with existing placeholder uuid=\(uuid) callId=\(call.id) userId=\(call.userId)",
            )
        } else {
            uuid = UUID()
            TelegramCallSession.prepareAudioSession()
            currentCallUUID = uuid
            log(
                "[CallKit] reportIncoming reporting fresh (no placeholder) uuid=\(uuid) callId=\(call.id) userId=\(call.userId)",
            )
            provider.reportNewIncomingCall(with: uuid, update: Self.update(displayName: nil)) { [weak self] error in
                guard let error else { return }
                Task { @MainActor [weak self] in
                    log("[CallKit] failed to report incoming call: \(error)")
                    self?.clearCurrentCall(ifMatching: uuid)
                }
            }
        }
        currentUserId = call.userId
        currentTelegramCallUniqueId = call.uniqueId.rawValue
        isCurrentCallOutgoing = false

        Task { [weak self] in
            guard let self, let user = try? await TDLib.shared.service.getUser(userId: call.userId) else { return }
            let name = [user.firstName, user.lastName].filter { !$0.isEmpty }.joined(separator: " ")
            guard !name.isEmpty, currentCallUUID == uuid else { return }
            log("[CallKit] updating caller display name to \(name)")
            provider.reportCall(with: uuid, updated: Self.update(displayName: name))
        }
    }

    private func reportConnected() {
        guard let uuid = currentCallUUID, isCurrentCallOutgoing else {
            log(
                "[CallKit] reportConnected no-op, currentCallUUID=\(currentCallUUID?.uuidString ?? "nil") isCurrentCallOutgoing=\(isCurrentCallOutgoing)",
            )
            return
        }
        log("[CallKit] reportConnected uuid=\(uuid)")
        provider.reportOutgoingCall(with: uuid, connectedAt: nil)
    }

    private func reportEnded() {
        guard let uuid = currentCallUUID else {
            log("[CallKit] reportEnded no-op, currentCallUUID=nil")
            return
        }
        log("[CallKit] reportEnded uuid=\(uuid)")
        if let uniqueId = currentTelegramCallUniqueId {
            recentlyEndedCallUniqueIds[uniqueId] = Foundation.Date()
        }
        if !isEndingLocally {
            provider.reportCall(with: uuid, endedAt: nil, reason: .remoteEnded)
        }
        clearCurrentCall(ifMatching: uuid)
    }

    private func clearCurrentCall(ifMatching uuid: UUID? = nil) {
        if let uuid, currentCallUUID != uuid {
            return
        }
        currentCallUUID = nil
        currentUserId = nil
        currentTelegramCallUniqueId = nil
        isCurrentCallOutgoing = false
        isEndingLocally = false
        isRequestingEndCall = false
    }

    private func pruneRecentlyEndedCalls() {
        let cutoff = Foundation.Date().addingTimeInterval(-60)
        recentlyEndedCallUniqueIds = recentlyEndedCallUniqueIds.filter { $0.value >= cutoff }
    }
}

// MARK: @MainActor CXProviderDelegate

extension CallKitManager: @MainActor CXProviderDelegate {
    func providerDidReset(_: CXProvider) {
        log("[CallKit] providerDidReset")
        TelegramCallSession.shared.endFromSystem()
        TelegramCallSession.shared.cancelPendingSystemAction()
        clearCurrentCall()
    }

    func provider(_: CXProvider, perform action: CXAnswerCallAction) {
        log(
            "[CallKit] perform CXAnswerCallAction uuid=\(action.callUUID) currentCallUUID=\(currentCallUUID?.uuidString ?? "nil") currentUserId=\(currentUserId.map(String.init) ?? "nil")",
        )
        guard currentCallUUID == action.callUUID else {
            action.fail()
            return
        }
        Task {
            let granted = await AVAudioApplication.requestRecordPermission()
            guard granted else {
                log("[CallKit] microphone permission denied; incoming call rejected")
                TelegramCallSession.shared.endFromSystem()
                isEndingLocally = true
                provider.reportCall(with: action.callUUID, endedAt: nil, reason: .failed)
                clearCurrentCall(ifMatching: action.callUUID)
                action.fail()
                return
            }
            TelegramCallSession.shared.answerFromSystem()
            action.fulfill()
        }
    }

    func provider(_: CXProvider, perform action: CXEndCallAction) {
        log("[CallKit] perform CXEndCallAction uuid=\(action.callUUID)")
        isRequestingEndCall = false
        guard currentCallUUID == action.callUUID else {
            action.fail()
            return
        }
        isEndingLocally = true
        TelegramCallSession.shared.endFromSystem { [weak self] succeeded in
            guard let self else {
                action.fail()
                return
            }
            if succeeded {
                action.fulfill(withDateEnded: Foundation.Date())
            } else {
                isEndingLocally = false
                action.fail()
            }
        }
    }

    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        log(
            "[CallKit] perform CXStartCallAction uuid=\(action.callUUID) currentUserId=\(currentUserId.map(String.init) ?? "nil")",
        )
        guard let userId = currentUserId, currentCallUUID == action.callUUID else {
            action.fail()
            return
        }
        provider.reportOutgoingCall(with: action.callUUID, startedConnectingAt: nil)
        TelegramCallSession.shared.startCall(userId: userId) { [weak self] succeeded in
            guard succeeded else {
                action.fail()
                self?.clearCurrentCall(ifMatching: action.callUUID)
                return
            }
            action.fulfill()
        }
    }

    func provider(_: CXProvider, perform action: CXSetMutedCallAction) {
        log("[CallKit] perform CXSetMutedCallAction muted=\(action.isMuted)")
        guard currentCallUUID == action.callUUID else {
            action.fail()
            return
        }
        TelegramCallSession.shared.setMuted(action.isMuted)
        action.fulfill()
    }

    nonisolated func provider(_: CXProvider, didActivate _: AVAudioSession) {
        Task { @MainActor in
            log("[CallKit] didActivate audio session")
            audioSessionActiveSubject.send(true)
        }
    }

    nonisolated func provider(_: CXProvider, didDeactivate _: AVAudioSession) {
        Task { @MainActor in
            log("[CallKit] didDeactivate audio session")
            audioSessionActiveSubject.send(false)
        }
    }
}
