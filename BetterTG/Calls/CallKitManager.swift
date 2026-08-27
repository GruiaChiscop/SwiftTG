// CallKitManager.swift

import AVFoundation
import CallKit
import Combine
import Foundation
import Intents
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
        configuration.supportsVideo = true
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
        session.onCallEnded = { [weak self] reason in self?.reportEnded(reason: reason) }
    }

    /// Routes an outgoing call through CallKit's own `CXStartCallAction` first, matching Apple's
    /// required flow, rather than calling `TelegramCallSession.startCall` directly - the actual
    /// `createCall` only happens once CallKit grants the action in
    /// `provider(_:perform: CXStartCallAction)` below.
    func startOutgoingCall(
        userId: Int64,
        displayName: String,
        isVideo: Bool = false,
        onCameraPermissionDenied: @escaping () -> Void = {},
    ) {
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
            if isVideo {
                let cameraGranted = await Self.requestCameraAccess()
                guard cameraGranted else {
                    isRequestingOutgoingCall = false
                    log("[CallKit] camera permission denied; outgoing video call not started")
                    onCameraPermissionDenied()
                    return
                }
            }
            guard isRequestingOutgoingCall, currentCallUUID == nil else {
                isRequestingOutgoingCall = false
                log("[CallKit] outgoing call superseded while waiting for microphone permission")
                return
            }

            TelegramCallSession.prepareAudioSession()
            let uuid = UUID()
            currentCallUUID = uuid
            currentUserId = userId
            isCurrentCallOutgoing = true
            isRequestingOutgoingCall = false

            let name = displayName.isEmpty ? "Telegram" : displayName
            let visibleHandle = Self.callKitHandle(displayName: name)
            let action = CXStartCallAction(call: uuid, handle: visibleHandle)
            action.isVideo = isVideo
            do {
                try await callController.request(CXTransaction(action: action))
                guard currentCallUUID == uuid else { return }
                provider.reportCall(
                    with: uuid,
                    updated: Self.update(handle: visibleHandle, displayName: name, hasVideo: isVideo),
                )
                Self.donateCallIntent(userId: userId, displayName: name, isVideo: isVideo)
            } catch {
                log("CallKit start request failed: \(error)")
                clearCurrentCall(ifMatching: uuid)
            }
        }
    }

    /// Handles a call donated to Phone/Siri and returned to the app through `NSUserActivity`.
    /// A cold launch can deliver the intent before TDLib restores authorization, so wait for its
    /// real ready state rather than racing `createCall` against session startup.
    @discardableResult func startOutgoingCall(from contacts: [INPerson]?, isVideo: Bool = false) -> Bool {
        guard let person = contacts?.first,
              let userId = Self.telegramUserId(from: person)
        else {
            log("[CallKit] ignoring start-call intent without a Telegram user handle")
            return false
        }

        intentStartGeneration &+= 1
        let generation = intentStartGeneration
        pendingIntentStartTask?.cancel()
        pendingIntentStartTask = Task { [weak self] in
            guard let self else { return }
            let isReady = await Self.waitUntilTelegramReady(timeoutSeconds: 10)
            guard !Task.isCancelled, intentStartGeneration == generation else { return }
            pendingIntentStartTask = nil
            guard isReady else {
                log("[CallKit] start-call intent timed out waiting for TDLib authorization")
                return
            }
            startOutgoingCall(userId: userId, displayName: person.displayName, isVideo: isVideo)
        }
        return true
    }

    /// App-initiated hangups must travel through CallKit too. This keeps the system call UI and
    /// TDLib lifecycle on the same transaction, matching Telegram-iOS's `endCall(uuid:)` flow.
    func requestEndCall(onFailure: @escaping () -> Void = {}) {
        guard let uuid = currentCallUUID else {
            // SwiftUI writes `false` back into the presentation binding when the call's terminal
            // update dismisses CallView. That is not a new system End action and must never be
            // deferred onto the next call.
            log("[CallKit] ignoring app End request with no active CallKit call")
            onFailure()
            return
        }
        guard !isRequestingEndCall, !isEndingLocally else {
            onFailure()
            return
        }
        isRequestingEndCall = true
        Task { [weak self] in
            guard let self else { return }
            do {
                try await callController.request(CXTransaction(action: CXEndCallAction(call: uuid)))
            } catch {
                if currentCallUUID == uuid {
                    isRequestingEndCall = false
                }
                log("CallKit end request failed: \(error)")
                onFailure()
            }
        }
    }

    /// App-initiated mute changes must also pass through CallKit so the in-app control and the
    /// system call surfaces always agree on whether the microphone is muted.
    func requestSetMuted(_ muted: Bool) {
        guard let uuid = currentCallUUID else {
            log("[CallKit] ignoring app mute request with no active CallKit call")
            return
        }
        guard requestedMutedValue == nil else { return }
        requestedMutedValue = muted
        Task { [weak self] in
            guard let self else { return }
            do {
                try await callController.request(CXTransaction(
                    action: CXSetMutedCallAction(call: uuid, muted: muted),
                ))
            } catch {
                if currentCallUUID == uuid, requestedMutedValue == muted {
                    requestedMutedValue = nil
                }
                log("CallKit mute request failed: \(error)")
            }
        }
    }

    /// Telegram-iOS replaces the private peer handle with an opaque conference handle as soon as
    /// the group transport takes over, so CallKit and Recents describe the ongoing call correctly.
    func updateCurrentCallAsConference() {
        guard let uuid = currentCallUUID else { return }
        let handle = CXHandle(type: .generic, value: uuid.uuidString)
        provider.reportCall(
            with: uuid,
            updated: Self.update(handle: handle, displayName: "Group Call"),
        )
        log("[CallKit] updated uuid=\(uuid) as conference")
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
        provider.reportNewIncomingCall(
            with: uuid,
            update: Self.update(handle: Self.callKitHandle(displayName: nil), displayName: nil),
        ) { [weak self] error in
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
    private var requestedMutedValue: Bool?
    private var intentStartGeneration: UInt64 = 0
    private var pendingIntentStartTask: Task<Void, Never>?

    private static func callKitHandle(displayName: String?) -> CXHandle {
        let value = displayName.flatMap { $0.isEmpty ? nil : $0 } ?? "Telegram"
        return CXHandle(type: .generic, value: value)
    }

    private static func telegramRedialIdentifier(userId: Int64) -> String {
        "tg:\(userId)"
    }

    private static func telegramCallHandle(userId: Int64) -> CXHandle {
        CXHandle(type: .generic, value: telegramRedialIdentifier(userId: userId))
    }

    private static func telegramUserId(from person: INPerson) -> Int64? {
        for value in [person.customIdentifier, person.personHandle?.value].compactMap(\.self) {
            if let userId = telegramUserId(fromHandleValue: value) {
                return userId
            }
        }
        return nil
    }

    private static func telegramUserId(fromHandleValue value: String) -> Int64? {
        guard value.hasPrefix("tg:") else { return nil }
        return Int64(value.dropFirst(3))
    }

    private static func donateCallIntent(userId: Int64, displayName: String, isVideo: Bool) {
        let value = telegramRedialIdentifier(userId: userId)
        let person = INPerson(
            personHandle: INPersonHandle(value: value, type: .unknown),
            nameComponents: nil,
            displayName: displayName,
            image: nil,
            contactIdentifier: nil,
            customIdentifier: value,
        )
        let intent = INStartCallIntent(
            callRecordFilter: nil,
            callRecordToCallBack: nil,
            audioRoute: .unknown,
            destinationType: .normal,
            contacts: [person],
            callCapability: isVideo ? .videoCall : .audioCall,
        )
        let interaction = INInteraction(intent: intent, response: nil)
        interaction.direction = .outgoing
        interaction.donate { error in
            if let error {
                log("[CallKit] failed to donate start-call intent: \(error)")
            } else {
                log("[CallKit] donated start-call intent userId=\(userId)")
            }
        }
    }

    private static func waitUntilTelegramReady(timeoutSeconds: Double) async -> Bool {
        if let state = try? await TDLib.shared.service.getAuthorizationState(),
           case .authorizationStateReady = state
        {
            return true
        }

        return await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                for await state in TDLib.shared.service.authorizationStatePublisher.values {
                    if case .authorizationStateReady = state {
                        return true
                    }
                    if Task.isCancelled {
                        return false
                    }
                }
                return false
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(timeoutSeconds))
                return false
            }
            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }
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

    private static func update(handle: CXHandle, displayName: String?, hasVideo: Bool = false) -> CXCallUpdate {
        let update = CXCallUpdate()
        update.remoteHandle = handle
        update.localizedCallerName = displayName
        update.hasVideo = hasVideo
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
            provider.reportNewIncomingCall(
                with: uuid,
                update: Self.update(
                    handle: Self.telegramCallHandle(userId: call.userId),
                    displayName: "Telegram",
                    hasVideo: call.isVideo,
                ),
            ) { [weak self] error in
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
        let handle = Self.telegramCallHandle(userId: call.userId)
        provider.reportCall(
            with: uuid,
            updated: Self.update(handle: handle, displayName: "Telegram", hasVideo: call.isVideo),
        )

        Task { [weak self] in
            guard let self, let user = try? await TDLib.shared.service.getUser(userId: call.userId) else { return }
            let name = [user.firstName, user.lastName].filter { !$0.isEmpty }.joined(separator: " ")
            guard !name.isEmpty, currentCallUUID == uuid else { return }
            log("[CallKit] updating caller display name to \(name)")
            provider.reportCall(
                with: uuid,
                updated: Self.update(handle: handle, displayName: name, hasVideo: call.isVideo),
            )
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

    private func reportEnded(reason: TelegramCallSession.EndReason) {
        guard let uuid = currentCallUUID else {
            log("[CallKit] reportEnded no-op, currentCallUUID=nil")
            return
        }
        let callKitReason: CXCallEndedReason =
            switch reason {
            case .failed: .failed
            case .remoteEnded: .remoteEnded
            case .unanswered: .unanswered
            }
        log("[CallKit] reportEnded uuid=\(uuid) reason=\(callKitReason.rawValue)")
        if let uniqueId = currentTelegramCallUniqueId {
            recentlyEndedCallUniqueIds[uniqueId] = Foundation.Date()
        }
        if !isEndingLocally {
            provider.reportCall(with: uuid, endedAt: nil, reason: callKitReason)
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
        requestedMutedValue = nil
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
            guard currentCallUUID == action.callUUID else {
                log("[CallKit] answer action superseded while waiting for microphone permission")
                action.fail()
                return
            }
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
        guard currentCallUUID == action.callUUID else {
            action.fail()
            return
        }
        isRequestingEndCall = false
        isEndingLocally = true
        TelegramCallSession.shared.endFromSystem { [weak self] succeeded in
            guard let self else {
                action.fail()
                return
            }
            if succeeded {
                action.fulfill(withDateEnded: Foundation.Date())
            } else {
                if currentCallUUID == action.callUUID {
                    isEndingLocally = false
                }
                action.fail()
            }
        }
    }

    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        log(
            "[CallKit] perform CXStartCallAction uuid=\(action.callUUID) currentUserId=\(currentUserId.map(String.init) ?? "nil")",
        )
        let userId: Int64
        if let currentUserId, currentCallUUID == action.callUUID {
            userId = currentUserId
        } else if currentCallUUID == nil,
                  TelegramCallSession.shared.activeCall == nil,
                  let resumedUserId = Self.telegramUserId(fromHandleValue: action.handle.value)
        {
            TelegramCallSession.prepareAudioSession()
            currentCallUUID = action.callUUID
            currentUserId = resumedUserId
            isCurrentCallOutgoing = true
            userId = resumedUserId
            log("[CallKit] resolved system start action to Telegram userId=\(resumedUserId)")
        } else {
            action.fail()
            return
        }
        provider.reportOutgoingCall(with: action.callUUID, startedConnectingAt: nil)
        TelegramCallSession.shared.startCall(userId: userId, isVideo: action.isVideo) { [weak self] succeeded in
            guard let self, currentCallUUID == action.callUUID else {
                log("[CallKit] start action superseded before createCall completed")
                action.fail()
                return
            }
            guard succeeded else {
                action.fail()
                clearCurrentCall(ifMatching: action.callUUID)
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
        requestedMutedValue = nil
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
