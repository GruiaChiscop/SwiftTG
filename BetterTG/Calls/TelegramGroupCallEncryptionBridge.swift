// TelegramGroupCallEncryptionBridge.swift

import Foundation
import TDLibKit

// MARK: - TelegramGroupCallEncryptionBridge

/// Adapts TDLib's callback-based E2E operations to tgcalls' synchronous packet callback. TDLib
/// performs both operations locally; the bounded wait prevents a stopped TDLib session from ever
/// wedging the media queue during teardown.
final class TelegramGroupCallEncryptionBridge: Sendable {
    // MARK: Lifecycle

    init(service: any TelegramService) {
        self.service = service
    }

    // MARK: Internal

    enum Channel: Sendable {
        case main
        case screenSharing
    }

    func makeEncryption(channel: Channel = .main) -> TelegramGroupCallEngine.Encryption {
        TelegramGroupCallEngine.Encryption(
            encrypt: { [self] data, unencryptedPrefixSize in
                guard let groupCallId = identifier.value else { return nil }
                return perform { completion in
                    service.encryptGroupCallData(
                        data: data,
                        dataChannel: tdlibChannel(channel),
                        groupCallId: groupCallId,
                        unencryptedPrefixSize: Int(unencryptedPrefixSize),
                        completion: completion,
                    )
                }
            },
            decrypt: { [self] data, userId in
                guard let groupCallId = identifier.value else { return nil }
                return perform { completion in
                    service.decryptGroupCallData(
                        data: data,
                        dataChannel: tdlibChannel(channel),
                        groupCallId: groupCallId,
                        participantId: .messageSenderUser(.init(userId: userId)),
                        completion: completion,
                    )
                }
            },
        )
    }

    func setGroupCallId(_ groupCallId: Int) {
        identifier.value = groupCallId
    }

    // MARK: Private

    private let service: any TelegramService
    private let identifier = GroupCallIdentifier()

    private func tdlibChannel(_ channel: Channel) -> GroupCallDataChannel {
        switch channel {
        case .main:
            .groupCallDataChannelMain
        case .screenSharing:
            .groupCallDataChannelScreenSharing
        }
    }

    private func perform(_ operation: (@escaping @Sendable (Data?) -> Void) -> Void) -> Data? {
        let request = GroupCallDataRequest()
        operation { data in
            request.complete(with: data)
        }
        return request.wait(timeout: 0.5)
    }
}

// MARK: - GroupCallIdentifier

private final class GroupCallIdentifier: @unchecked Sendable {
    // MARK: Internal

    var value: Int? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedValue
        }
        set {
            lock.lock()
            storedValue = newValue
            lock.unlock()
        }
    }

    // MARK: Private

    private let lock = NSLock()
    private var storedValue: Int?
}

// MARK: - GroupCallDataRequest

/// `NSCondition` protects both fields and makes this synchronous bridge safe to move between
/// TDLib's response queue and tgcalls' media queue.
private final class GroupCallDataRequest: @unchecked Sendable {
    // MARK: Internal

    func complete(with data: Data?) {
        condition.lock()
        guard !isComplete else {
            condition.unlock()
            return
        }
        result = data
        isComplete = true
        condition.broadcast()
        condition.unlock()
    }

    func wait(timeout: TimeInterval) -> Data? {
        condition.lock()
        let deadline = Date(timeIntervalSinceNow: timeout)
        while !isComplete {
            if !condition.wait(until: deadline) {
                break
            }
        }
        let result = result
        condition.unlock()
        return result
    }

    // MARK: Private

    private let condition = NSCondition()
    private var isComplete = false
    private var result: Data?
}
