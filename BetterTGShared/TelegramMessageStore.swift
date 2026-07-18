// TelegramMessageStore.swift

import Combine
import Foundation
@preconcurrency import TDLibKit

// MARK: - TelegramMessageChange

enum TelegramMessageChange: Sendable {
    case chatAction(UpdateChatAction)
    case deleteMessages(UpdateDeleteMessages)
    case historyMerged
    case messageEdited(UpdateMessageEdited)
    case messageInteractionInfo(UpdateMessageInteractionInfo)
    case messagePinChanged(UpdateMessageIsPinned)
    case messageSendSucceeded(UpdateMessageSendSucceeded)
    case newMessage(UpdateNewMessage)
    case readInbox(UpdateChatReadInbox)
    case readOutbox(UpdateChatReadOutbox)
    case userStatus(UpdateUserStatus)
}

// MARK: - TelegramMessageSnapshot

struct TelegramMessageSnapshot: Sendable {
    let chatId: Int64
    let version: UInt64
    let messages: [Int64: Message]
    let orderedMessageIds: [Int64]
    let unreadCount: Int?
    let hasMergedHistory: Bool
    let change: TelegramMessageChange?

    static func empty(chatId: Int64) -> TelegramMessageSnapshot {
        TelegramMessageSnapshot(
            chatId: chatId,
            version: 0,
            messages: [:],
            orderedMessageIds: [],
            unreadCount: nil,
            hasMergedHistory: false,
            change: nil,
        )
    }

    func withoutChange() -> TelegramMessageSnapshot {
        TelegramMessageSnapshot(
            chatId: chatId,
            version: version,
            messages: messages,
            orderedMessageIds: orderedMessageIds,
            unreadCount: unreadCount,
            hasMergedHistory: hasMergedHistory,
            change: nil,
        )
    }
}

// MARK: - TelegramMessageStore

final class TelegramMessageStore: @unchecked Sendable {
    // MARK: Internal

    func publisher(chatId: Int64) -> AnyPublisher<TelegramMessageSnapshot, Never> {
        stateLock.withLock {
            let initialSnapshot = (snapshots[chatId] ?? .empty(chatId: chatId)).withoutChange()
            let subject: CurrentValueSubject<TelegramMessageSnapshot, Never>
            if let existingSubject = subjects[chatId] {
                subject = existingSubject
            } else {
                subject = CurrentValueSubject(initialSnapshot)
                subjects[chatId] = subject
            }
            return subject
                .scan((isFirst: true, snapshot: initialSnapshot)) { state, snapshot in
                    (isFirst: false, snapshot: state.isFirst ? snapshot.withoutChange() : snapshot)
                }
                .map(\.snapshot)
                .eraseToAnyPublisher()
        }
    }

    func mergeHistory(chatId: Int64, messages: [Message]) {
        merge(chatId: chatId, messages: messages, marksHistoryLoaded: true)
    }

    func replaceHistory(chatId: Int64, messages: [Message]) {
        guard !messages.isEmpty else { return }
        queue.async {
            let snapshot = self.snapshots[chatId] ?? .empty(chatId: chatId)
            let deletedIds = self.deletedMessageIds[chatId] ?? []
            let replacement = messages.filter { !deletedIds.contains($0.id) }
            guard let newestReplacement = replacement.max(by: Self.isOrderedBefore) else { return }

            // An update may have arrived while TDLib was fetching the latest page.
            // Keep that live tail, as well as pending outgoing messages, while
            // discarding the disconnected history slice that was previously shown.
            let liveTail = snapshot.messages.values.filter { message in
                guard !deletedIds.contains(message.id),
                      !replacement.contains(where: { $0.id == message.id })
                else { return false }
                return message.id < 0 || Self.isOrderedBefore(newestReplacement, message)
            }
            let visibleMessages = replacement + liveTail
            let storedMessages = Dictionary(uniqueKeysWithValues: visibleMessages.map { ($0.id, $0) })
            let orderedIds = storedMessages.keys.sorted { lhs, rhs in
                guard let lhsMessage = storedMessages[lhs], let rhsMessage = storedMessages[rhs] else {
                    return lhs < rhs
                }
                return Self.isOrderedBefore(lhsMessage, rhsMessage)
            }

            self.publish(TelegramMessageSnapshot(
                chatId: chatId,
                version: snapshot.version + 1,
                messages: storedMessages,
                orderedMessageIds: orderedIds,
                unreadCount: snapshot.unreadCount,
                hasMergedHistory: true,
                change: .historyMerged,
            ))
        }
    }

    func mergeMessages(chatId: Int64, messages: [Message]) {
        merge(chatId: chatId, messages: messages, marksHistoryLoaded: false)
    }

    func reduce(_ update: Update) {
        if case .updateMessageSendFailed(let value) = update {
            TelegramVoiceNoteStaging.shared.messageSendFailed(
                chatId: value.message.chatId,
                oldMessageId: value.oldMessageId,
                failedMessageId: value.message.id,
            )
        }
        guard let reduction = reduction(for: update) else { return }
        queue.async {
            let chatId = reduction.chatId
            var snapshot = self.snapshots[chatId] ?? .empty(chatId: chatId)
            var messages = snapshot.messages
            var orderedIds = snapshot.orderedMessageIds
            var unreadCount = snapshot.unreadCount

            switch reduction.change {
            case .newMessage(let value):
                self.deletedMessageIds[chatId]?.remove(value.message.id)
                messages[value.message.id] = value.message
                if !orderedIds.contains(value.message.id) {
                    orderedIds.append(value.message.id)
                }
            case .deleteMessages(let value):
                guard !value.fromCache, value.isPermanent else { return }
                TelegramVoiceNoteStaging.shared.messagesDeleted(
                    chatId: chatId,
                    messageIds: value.messageIds,
                )
                for messageId in value.messageIds {
                    messages[messageId] = nil
                    self.deletedMessageIds[chatId, default: []].insert(messageId)
                }
                orderedIds.removeAll { value.messageIds.contains($0) }
            case .messageSendSucceeded(let value):
                TelegramVoiceNoteStaging.shared.messageSendSucceeded(
                    chatId: chatId,
                    oldMessageId: value.oldMessageId,
                )
                self.deletedMessageIds[chatId]?.remove(value.message.id)
                messages[value.oldMessageId] = nil
                messages[value.message.id] = value.message
                if let index = orderedIds.firstIndex(of: value.oldMessageId) {
                    orderedIds[index] = value.message.id
                } else if !orderedIds.contains(value.message.id) {
                    orderedIds.append(value.message.id)
                }
            case .readInbox(let value):
                unreadCount = value.unreadCount
            case .chatAction, .historyMerged, .messageEdited, .messageInteractionInfo, .messagePinChanged, .readOutbox,
                 .userStatus:
                break
            }

            snapshot = TelegramMessageSnapshot(
                chatId: chatId,
                version: snapshot.version + 1,
                messages: messages,
                orderedMessageIds: orderedIds,
                unreadCount: unreadCount,
                hasMergedHistory: snapshot.hasMergedHistory,
                change: reduction.change,
            )
            self.publish(snapshot)
        }
    }

    // MARK: Private

    private let queue = DispatchQueue(label: "com.gruiachiscop.BetterTG.telegram-messages")
    private let stateLock = NSLock()
    private var deletedMessageIds = [Int64: Set<Int64>]()
    private var snapshots = [Int64: TelegramMessageSnapshot]()
    private var subjects = [Int64: CurrentValueSubject<TelegramMessageSnapshot, Never>]()

    private static func isOrderedBefore(_ lhs: Message, _ rhs: Message) -> Bool {
        if lhs.date == rhs.date {
            return lhs.id < rhs.id
        }
        return lhs.date < rhs.date
    }

    private func merge(chatId: Int64, messages: [Message], marksHistoryLoaded: Bool) {
        queue.async {
            var snapshot = self.snapshots[chatId] ?? .empty(chatId: chatId)
            var storedMessages = snapshot.messages
            var orderedIds = snapshot.orderedMessageIds
            let deletedIds = self.deletedMessageIds[chatId] ?? []

            for message in messages {
                guard !deletedIds.contains(message.id) else { continue }
                storedMessages[message.id] = message
                if !orderedIds.contains(message.id) {
                    orderedIds.append(message.id)
                }
            }
            orderedIds.sort { lhs, rhs in
                guard let lhsMessage = storedMessages[lhs], let rhsMessage = storedMessages[rhs] else {
                    return lhs < rhs
                }
                if lhsMessage.date == rhsMessage.date {
                    return lhsMessage.id < rhsMessage.id
                }
                return lhsMessage.date < rhsMessage.date
            }

            snapshot = TelegramMessageSnapshot(
                chatId: chatId,
                version: snapshot.version + 1,
                messages: storedMessages,
                orderedMessageIds: orderedIds,
                unreadCount: snapshot.unreadCount,
                hasMergedHistory: snapshot.hasMergedHistory || marksHistoryLoaded,
                change: .historyMerged,
            )
            self.publish(snapshot)
        }
    }

    private func publish(_ snapshot: TelegramMessageSnapshot) {
        dispatchPrecondition(condition: .onQueue(queue))
        let subject = stateLock.withLock {
            snapshots[snapshot.chatId] = snapshot
            return subjects[snapshot.chatId]
        }
        subject?.send(snapshot)
    }

    private func reduction(for update: Update) -> (chatId: Int64, change: TelegramMessageChange)? {
        switch update {
        case .updateChatAction(let value):
            (value.chatId, .chatAction(value))
        case .updateChatReadInbox(let value):
            (value.chatId, .readInbox(value))
        case .updateChatReadOutbox(let value):
            (value.chatId, .readOutbox(value))
        case .updateDeleteMessages(let value):
            (value.chatId, .deleteMessages(value))
        case .updateMessageEdited(let value):
            (value.chatId, .messageEdited(value))
        case .updateMessageInteractionInfo(let value):
            (value.chatId, .messageInteractionInfo(value))
        case .updateMessageIsPinned(let value):
            (value.chatId, .messagePinChanged(value))
        case .updateMessageSendSucceeded(let value):
            (value.message.chatId, .messageSendSucceeded(value))
        case .updateNewMessage(let value):
            (value.message.chatId, .newMessage(value))
        case .updateUserStatus(let value):
            (value.userId, .userStatus(value))
        default:
            nil
        }
    }
}
