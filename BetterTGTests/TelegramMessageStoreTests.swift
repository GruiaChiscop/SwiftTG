// TelegramMessageStoreTests.swift

@testable import BetterTG
import Combine
import Foundation
import TDLibKit
import Testing

struct TelegramMessageStoreTests {
    // MARK: Internal

    @Test func `history merge orders messages and marks history loaded`() throws {
        let store = TelegramMessageStore()
        let chatId: Int64 = 10
        let older = TDLibFixtures.message(id: 1, chatId: chatId, date: 100)
        let newer = TDLibFixtures.message(id: 2, chatId: chatId, date: 200)

        let snapshot = try waitForSnapshot(store: store, chatId: chatId, matching: {
            $0.hasMergedHistory && $0.messages.count == 2
        }) {
            store.mergeHistory(chatId: chatId, messages: [newer, older])
        }

        #expect(snapshot.orderedMessageIds == [older.id, newer.id])
        #expect(snapshot.version == 1)
        guard case .historyMerged = snapshot.change else {
            Issue.record("Expected a history merge change")
            return
        }
    }

    @Test func `permanent deletion is not undone by stale history`() throws {
        let store = TelegramMessageStore()
        let chatId: Int64 = 20
        let message = TDLibFixtures.message(id: 5, chatId: chatId, date: 100)

        let snapshot = try waitForSnapshot(store: store, chatId: chatId, matching: {
            $0.hasMergedHistory && $0.version >= 3
        }) {
            store.mergeMessages(chatId: chatId, messages: [message])
            store.reduce(.updateDeleteMessages(.init(
                chatId: chatId,
                fromCache: false,
                isPermanent: true,
                messageIds: [message.id],
            )))
            store.mergeHistory(chatId: chatId, messages: [message])
        }

        #expect(snapshot.messages[message.id] == nil)
        #expect(!snapshot.orderedMessageIds.contains(message.id))
    }

    @Test func `history replacement discards disconnected slice and preserves live tail`() throws {
        let store = TelegramMessageStore()
        let chatId: Int64 = 25
        let disconnected = TDLibFixtures.message(id: 1, chatId: chatId, date: 100)
        let latest = TDLibFixtures.message(id: 10, chatId: chatId, date: 1000)
        let live = TDLibFixtures.message(id: 11, chatId: chatId, date: 1100)

        let snapshot = try waitForSnapshot(store: store, chatId: chatId, matching: {
            $0.version >= 3 && $0.messages[latest.id] != nil
        }) {
            store.mergeHistory(chatId: chatId, messages: [disconnected])
            store.reduce(.updateNewMessage(.init(message: live)))
            store.replaceHistory(chatId: chatId, messages: [latest])
        }

        #expect(snapshot.orderedMessageIds == [latest.id, live.id])
        #expect(snapshot.messages[disconnected.id] == nil)
    }

    @Test func `new message can restore an identifier after A deletion`() throws {
        let store = TelegramMessageStore()
        let chatId: Int64 = 30
        let message = TDLibFixtures.message(id: 6, chatId: chatId, date: 100)

        let snapshot = try waitForSnapshot(store: store, chatId: chatId, matching: {
            $0.version >= 3 && $0.messages[message.id] != nil
        }) {
            store.mergeMessages(chatId: chatId, messages: [message])
            store.reduce(.updateDeleteMessages(.init(
                chatId: chatId,
                fromCache: false,
                isPermanent: true,
                messageIds: [message.id],
            )))
            store.reduce(.updateNewMessage(.init(message: message)))
        }

        #expect(snapshot.orderedMessageIds == [message.id])
        guard case .newMessage = snapshot.change else {
            Issue.record("Expected a new-message change")
            return
        }
    }

    @Test func `successful send replaces temporary message identifier`() throws {
        let store = TelegramMessageStore()
        let chatId: Int64 = 40
        let temporary = TDLibFixtures.message(id: -1, chatId: chatId, date: 100)
        let confirmed = TDLibFixtures.message(id: 10, chatId: chatId, date: 100)

        let snapshot = try waitForSnapshot(store: store, chatId: chatId, matching: {
            $0.messages[confirmed.id] != nil && $0.messages[temporary.id] == nil
        }) {
            store.mergeMessages(chatId: chatId, messages: [temporary])
            store.reduce(.updateMessageSendSucceeded(.init(
                message: confirmed,
                oldMessageId: temporary.id,
            )))
        }

        #expect(snapshot.orderedMessageIds == [confirmed.id])
    }

    @Test func `failed send replaces temporary message with failed message`() throws {
        let store = TelegramMessageStore()
        let chatId: Int64 = 41
        let temporary = TDLibFixtures.message(
            id: -1,
            chatId: chatId,
            date: 100,
            isOutgoing: true,
            sendingState: .messageSendingStatePending(.init(sendingId: 7)),
        )
        let error = TDLibKit.Error(code: 400, message: "STICKER_INVALID")
        let failed = TDLibFixtures.message(
            id: -2,
            chatId: chatId,
            date: 100,
            isOutgoing: true,
            sendingState: .messageSendingStateFailed(.init(
                canRetry: false,
                error: error,
                needAnotherReplyQuote: false,
                needAnotherSender: false,
                needDropReply: false,
                requiredPaidMessageStarCount: 0,
                retryAfter: 0,
            )),
        )

        let snapshot = try waitForSnapshot(store: store, chatId: chatId, matching: {
            $0.messages[failed.id] != nil && $0.messages[temporary.id] == nil
        }) {
            store.mergeMessages(chatId: chatId, messages: [temporary])
            store.reduce(.updateMessageSendFailed(.init(
                error: error,
                message: failed,
                oldMessageId: temporary.id,
            )))
        }

        #expect(snapshot.orderedMessageIds == [failed.id])
        guard case .messageSendFailed(let update) = snapshot.change else {
            Issue.record("Expected a message-send-failed change")
            return
        }
        #expect(update.error == error)
    }

    @Test func `first subscriber does not replay an old transient change`() throws {
        let store = TelegramMessageStore()
        let chatId: Int64 = 50
        let message = TDLibFixtures.message(id: 11, chatId: chatId, date: 100)
        _ = try waitForSnapshot(store: store, chatId: chatId, matching: {
            $0.messages[message.id] != nil
        }) {
            store.reduce(.updateNewMessage(.init(message: message)))
        }

        let initialSnapshot = try waitForSnapshot(store: store, chatId: chatId, matching: {
            $0.messages[message.id] != nil
        }) {}

        #expect(initialSnapshot.change == nil)
        #expect(initialSnapshot.messages[message.id] == message)
    }

    @Test func `retention is capped to the most recent messages regardless of how history arrived`() throws {
        let store = TelegramMessageStore()
        let chatId: Int64 = 70
        let firstBatch = (1...300).map { TDLibFixtures.message(id: Int64($0), chatId: chatId, date: $0) }
        let secondBatch = (301...600).map { TDLibFixtures.message(id: Int64($0), chatId: chatId, date: $0) }

        let snapshot = try waitForSnapshot(store: store, chatId: chatId, matching: {
            $0.messages[600] != nil
        }) {
            store.mergeHistory(chatId: chatId, messages: firstBatch)
            store.mergeHistory(chatId: chatId, messages: secondBatch)
        }

        #expect(snapshot.orderedMessageIds.count == 500)
        #expect(snapshot.orderedMessageIds == Array(101...600).map(Int64.init))
        #expect(snapshot.messages[100] == nil)
        #expect(snapshot.messages[101] != nil)
        #expect(snapshot.messages[600] != nil)
    }

    @Test func `interaction updates are published for the affected message`() throws {
        let store = TelegramMessageStore()
        let chatId: Int64 = 60
        let messageId: Int64 = 12

        let snapshot = try waitForSnapshot(store: store, chatId: chatId, matching: {
            if case .messageInteractionInfo(let update) = $0.change {
                return update.messageId == messageId
            }
            return false
        }) {
            store.reduce(.updateMessageInteractionInfo(.init(
                chatId: chatId,
                interactionInfo: nil,
                messageId: messageId,
            )))
        }

        guard case .messageInteractionInfo(let update) = snapshot.change else {
            Issue.record("Expected a message-interaction change")
            return
        }
        #expect(update.chatId == chatId)
        #expect(update.messageId == messageId)
    }

    // MARK: Private

    private func waitForSnapshot(
        store: TelegramMessageStore,
        chatId: Int64,
        matching predicate: @escaping (TelegramMessageSnapshot) -> Bool,
        perform: () -> Void,
    ) throws -> TelegramMessageSnapshot {
        let semaphore = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var result: TelegramMessageSnapshot?
        var didSignal = false
        let cancellable = store.publisher(chatId: chatId).sink { snapshot in
            lock.lock()
            defer { lock.unlock() }
            guard !didSignal, predicate(snapshot) else { return }
            didSignal = true
            result = snapshot
            semaphore.signal()
        }

        perform()
        let waitResult = semaphore.wait(timeout: .now() + 2)
        withExtendedLifetime(cancellable) {}
        #expect(waitResult == .success)
        return try #require(result)
    }
}
