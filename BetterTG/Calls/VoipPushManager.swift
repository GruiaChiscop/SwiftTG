// VoipPushManager.swift

import Combine
import Foundation
import PushKit
import TDLibKit

// MARK: - VoipPushManager

/// Registers for VoIP push notifications and wakes the app for incoming calls while it's not
/// otherwise running. Separate from `PushNotificationsManager` (regular APNs) because VoIP tokens
/// are a distinct `PKPushRegistry`/TDLib device-token type, with a stricter contract: every VoIP
/// push must result in a CallKit report (`CallKitManager.reportIncomingPlaceholder()`), synchronously,
/// or the OS can kill the app and eventually revoke its VoIP push entitlement.
@MainActor final class VoipPushManager: NSObject {
    // MARK: Lifecycle

    override private init() {
        super.init()
    }

    // MARK: Internal

    static let shared = VoipPushManager()

    func start() {
        registry.delegate = self
        registry.desiredPushTypes = [.voIP]
        authorizationSubscription = TDLib.shared
            .service
            .authorizationStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                let isReady =
                    if case .authorizationStateReady = state {
                        true
                    } else {
                        false
                    }
                self?.isTelegramReady = isReady
                if isReady {
                    self?.registerTokenIfPossible()
                }
            }
    }

    // MARK: Private

    private static var isAppSandbox: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    private let registry = PKPushRegistry(queue: .main)
    private var authorizationSubscription: AnyCancellable?
    private var isTelegramReady = false
    private var voipToken: String?
    private var registeredToken: String?
    private var registrationTask: Task<Void, Never>?
    private var registrationRetryTask: Task<Void, Never>?

    private nonisolated static func isOngoing(_ state: CallState) -> Bool {
        switch state {
        case .callStateDiscarded, .callStateError: false
        default: true
        }
    }

    /// Races the reactive `authorizationStatePublisher` against a bounded timeout, instead of
    /// polling - resolves the instant TDLib actually becomes ready (the common case takes well
    /// under a second once the session is restoring), with the timeout only as a safety bound for
    /// the rare case it doesn't. Mirrors Telegram-iOS's own VoIP push handler (`AppDelegate.swift`,
    /// `pushRegistryImpl`), which subscribes to its account-context Signal rather than sleeping.
    private func waitUntilTelegramReady(timeoutSeconds: Double) async {
        guard !isTelegramReady else { return }
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for await state in TDLib.shared.service.authorizationStatePublisher.values {
                    if case .authorizationStateReady = state {
                        return
                    }
                    if Task.isCancelled {
                        return
                    }
                }
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(timeoutSeconds))
            }
            await group.next()
            group.cancelAll()
        }
        if !isTelegramReady {
            log("VoIP push: TDLib still not ready after \(timeoutSeconds)s, processing anyway")
        }
    }

    /// The real call never comes from the push payload itself - confirmed directly in TDLib's C++
    /// source (`NotificationManager::process_push_notification_payload` unconditionally requires a
    /// `loc_key` field; phone/video call pushes only ever reach the `PHONE_CALL_`/`VIDEO_CALL_`
    /// branch when that key IS present, and even then TDLib just returns error 406 "connection to
    /// the server is required to fetch new data" - it never carries call data through the push at
    /// all). Telegram's servers send our push in the raw MTProto call shape instead (matching what a
    /// raw-MTProto client parses itself), which TDLib has no code path for, so `processPushNotification`
    /// reliably errors on it - that's expected, not a bug. The only way the real call arrives is via
    /// TDLib's live connection reconnecting and delivering `updateCall`, which `TelegramCallSession`
    /// already reports to CallKit the instant it happens via `onIncomingCall`, independent of this
    /// wait. This is purely a fallback so a placeholder doesn't ring forever if that never happens
    /// (e.g. a stale push for a call already cancelled) - mirrors Telegram-iOS's own
    /// `AppDelegate.pushRegistryImpl`, which drops its CallKit placeholder only on an explicit
    /// `.terminated` call-state signal, with no timeout at all for a real 1:1 call. We can't wait on
    /// that same signal (TDLib discards the raw payload before extracting a call id we could key off
    /// of), so this timeout has to be generous rather than absent - long enough for a real cold
    /// reconnect over a slow network, not tied to how long Telegram-iOS happens to wait.
    private func waitForCallUpdate(timeoutSeconds: Double) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for await call in TDLib.shared.service.callPublisher.values {
                    // `callPublisher` now delivers a call's terminal (discarded/error) state as-is,
                    // not collapsed to nil - see TelegramUpdateStore.publish - so a call that arrived
                    // and immediately ended must not be mistaken here for one still worth waiting on.
                    if let call, Self.isOngoing(call.state) {
                        return
                    }
                    if Task.isCancelled {
                        return
                    }
                }
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(timeoutSeconds))
            }
            await group.next()
            group.cancelAll()
        }
    }

    private func registerTokenIfPossible() {
        guard isTelegramReady, let voipToken, registeredToken != voipToken, registrationTask == nil else { return }
        let tokenToRegister = voipToken
        registrationRetryTask?.cancel()
        registrationRetryTask = nil
        registrationTask = Task { [weak self] in
            guard let self else { return }
            defer {
                registrationTask = nil
                if self.voipToken != tokenToRegister {
                    registerTokenIfPossible()
                }
            }
            do {
                // `encrypt: true` is load-bearing, not optional: TDLib only decrypts an incoming
                // VoIP push payload (NotificationManager::process_push_notification, checked
                // against td's own C++ source) if it finds a locally-registered encryption key
                // matching the push's receiver id. Without one, TDLib treats the payload as
                // already-plaintext and expects the shape a raw-MTProto client like Telegram-iOS
                // would send itself (call_id/updates/from_id, no loc_key) - which is exactly the
                // shape TDLib's own generic processPushNotification then fails to parse, since it
                // always requires loc_key. `encrypt: true` makes TDLib generate and register its
                // own key, so the server encrypts pushes into the shape TDLib actually expects.
                _ = try await TDLib.shared.service.registerDevice(
                    deviceToken: .deviceTokenApplePushVoIP(.init(
                        deviceToken: tokenToRegister,
                        encrypt: true,
                        isAppSandbox: Self.isAppSandbox,
                    )),
                    otherUserIds: [],
                )
                if self.voipToken == tokenToRegister {
                    registeredToken = tokenToRegister
                }
            } catch {
                log("VoIP device registration failed: \(error.localizedDescription)")
                scheduleRegistrationRetry(for: tokenToRegister)
            }
        }
    }

    private func scheduleRegistrationRetry(for token: String) {
        guard voipToken == token, registeredToken != token else { return }
        registrationRetryTask?.cancel()
        registrationRetryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard let self, !Task.isCancelled, voipToken == token else { return }
            registrationRetryTask = nil
            registerTokenIfPossible()
        }
    }
}

// MARK: @MainActor PKPushRegistryDelegate

extension VoipPushManager: @MainActor PKPushRegistryDelegate {
    func pushRegistry(_: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
        guard type == .voIP else { return }
        let updatedToken = pushCredentials.token.map { String(format: "%02x", $0) }.joined()
        if voipToken != updatedToken {
            registrationRetryTask?.cancel()
            registrationRetryTask = nil
        }
        voipToken = updatedToken
        registerTokenIfPossible()
    }

    func pushRegistry(_: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        guard type == .voIP else { return }
        voipToken = nil
        registeredToken = nil
        registrationTask?.cancel()
        registrationTask = nil
        registrationRetryTask?.cancel()
        registrationRetryTask = nil
    }

    func pushRegistry(
        _: PKPushRegistry,
        didReceiveIncomingPushWith payload: PKPushPayload,
        for type: PKPushType,
        completion: @escaping () -> Void,
    ) {
        guard type == .voIP else {
            completion()
            return
        }
        // Required within a very tight window of every VoIP push, well before there's time to
        // fetch the real call/caller - CallKitManager reconciles this placeholder with the real
        // call once TDLib's own updateCall arrives from processing the push below.
        let userInfo = payload.dictionaryPayload
        let didReportPlaceholder = CallKitManager.shared.reportIncomingPlaceholder(
            callUniqueId: Self.callUniqueId(from: userInfo),
        )
        // PushKit only requires that CallKit has been reported synchronously. Network/TDLib work
        // must not hold the system completion handler for several seconds.
        completion()

        Task { [weak self] in
            // A VoIP push can wake the app from a cold launch, before TDLib has finished restoring
            // its session - wait for that first, in case processPushNotification needs it (its own
            // doc comment says it can be called before authorization, so this may not be the actual
            // failure cause; kept as a no-cost precaution while the real cause is still open).
            await self?.waitUntilTelegramReady(timeoutSeconds: 8)
            do {
                let jsonPayload = try Self.jsonPayload(from: userInfo)
                log("VoIP push received; asking TDLib to reconnect/process it")
                // Reliably fails for call pushes - see the doc comment on `waitForCallUpdate` below
                // for why that's expected. Still worth calling: TDLib's own C++ handling forces its
                // connection online as a side effect of this call, before the parse even fails.
                _ = try await TDLib.shared.service.processPushNotification(payload: jsonPayload)
            } catch let error as TDLibKit.Error {
                // `TDLibKit.Error` isn't `LocalizedError`, so `.localizedDescription` always prints
                // the generic "(TDLibKit.Error error 1.)" Swift/NSError bridging fallback,
                // regardless of the real code/message inside - read the fields directly instead.
                log(
                    "VoIP push processing failed (expected for call pushes): code=\(error.code) message=\(error.message)",
                )
            } catch {
                log("VoIP push processing failed: \(error)")
            }
            if didReportPlaceholder {
                await self?.waitForCallUpdate(timeoutSeconds: 25)
                CallKitManager.shared.endPlaceholderIfStillPending()
            }
        }
    }

    private static func callUniqueId(from userInfo: [AnyHashable: Any]) -> Int64? {
        if let value = userInfo["call_id"] as? String {
            return Int64(value)
        }
        if let value = userInfo["call_id"] as? NSNumber {
            return value.int64Value
        }
        return nil
    }

    private static func jsonPayload(from userInfo: [AnyHashable: Any]) throws -> String {
        let payload = userInfo.reduce(into: [String: Any]()) { result, item in
            guard let key = item.key as? String else { return }
            result[key] = item.value
        }
        guard JSONSerialization.isValidJSONObject(payload) else {
            throw VoipPushError.invalidPayload
        }
        let data = try JSONSerialization.data(withJSONObject: payload)
        guard let json = String(data: data, encoding: .utf8) else {
            throw VoipPushError.invalidPayload
        }
        return json
    }
}

// MARK: - VoipPushError

private enum VoipPushError: Swift.Error {
    case invalidPayload
}
