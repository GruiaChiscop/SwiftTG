// TelegramApplePushRegistration.swift

import Combine
import Foundation
import TDLibKit

@MainActor final class TelegramApplePushRegistration {
    // MARK: Lifecycle

    init(service: any TelegramService, isAppSandbox: Bool) {
        self.service = service
        self.isAppSandbox = isAppSandbox
    }

    // MARK: Internal

    func start() {
        guard !isStarted else { return }
        isStarted = true
        observeAuthorizationState()
    }

    func stop() {
        isStarted = false
        authorizationSubscription?.cancel()
        authorizationSubscription = nil
        registrationTask?.cancel()
        registrationTask = nil
        isTelegramReady = false
    }

    func replaceService(_ service: any TelegramService) {
        authorizationSubscription?.cancel()
        registrationTask?.cancel()
        registrationTask = nil
        self.service = service
        serviceGeneration &+= 1
        isTelegramReady = false
        registeredToken = nil
        if isStarted {
            observeAuthorizationState()
        }
    }

    func didRegister(deviceToken: Data) {
        apnsToken = deviceToken.map { String(format: "%02x", $0) }.joined()
        registerTokenIfPossible()
    }

    func process(userInfo: [AnyHashable: Any]) async throws {
        let payload = userInfo.reduce(into: [String: Any]()) { result, item in
            guard let key = item.key as? String else { return }
            result[key] = item.value
        }
        guard JSONSerialization.isValidJSONObject(payload) else {
            throw PushError.invalidPayload
        }
        let data = try JSONSerialization.data(withJSONObject: payload)
        guard let json = String(data: data, encoding: .utf8) else {
            throw PushError.invalidPayload
        }
        _ = try await service.processPushNotification(payload: json)
    }

    // MARK: Private

    private enum PushError: Swift.Error {
        case invalidPayload
    }

    private var service: any TelegramService
    private let isAppSandbox: Bool
    private var apnsToken: String?
    private var authorizationSubscription: AnyCancellable?
    private var isStarted = false
    private var isTelegramReady = false
    private var registeredToken: String?
    private var registrationTask: Task<Void, Never>?
    private var serviceGeneration: UInt64 = 0

    private func observeAuthorizationState() {
        authorizationSubscription = service.authorizationStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard case .authorizationStateReady = state else { return }
                self?.isTelegramReady = true
                self?.registerTokenIfPossible()
            }
    }

    private func registerTokenIfPossible() {
        guard isTelegramReady,
              let apnsToken,
              registeredToken != apnsToken,
              registrationTask == nil
        else { return }

        let service = service
        let generation = serviceGeneration
        let isAppSandbox = isAppSandbox
        registrationTask = Task { [weak self] in
            defer {
                if self?.serviceGeneration == generation {
                    self?.registrationTask = nil
                }
            }
            do {
                _ = try await service.registerDevice(
                    deviceToken: .deviceTokenApplePush(.init(
                        deviceToken: apnsToken,
                        isAppSandbox: isAppSandbox,
                    )),
                    otherUserIds: [],
                )
                guard self?.serviceGeneration == generation else { return }
                self?.registeredToken = apnsToken
            } catch {
                guard !Task.isCancelled else { return }
                print("TDLib device registration failed: \(error.localizedDescription)")
            }
        }
    }
}
