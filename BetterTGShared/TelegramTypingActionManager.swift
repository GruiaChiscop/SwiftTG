// TelegramTypingActionManager.swift

import Foundation
import TDLibKit

/// Broadcasts the current user's composer activity (`sendChatAction`) to the other side of a chat.
///
/// Throttled the way Unigram's `OutputChatActionManager` does it: at most one send per `interval`
/// (4s). The server keeps a typing action alive for ~6s, so re-sending on the next keystroke that
/// lands after the interval is enough - no repeating timer. `cancel()` clears it early (message
/// sent, input emptied).
///
/// Construct one per opened chat; `isEnabled` is `false` for channels and Saved Messages, where
/// there is nobody to notify.
@MainActor final class TelegramTypingActionManager {
    // MARK: Lifecycle

    init(
        service: any TelegramService,
        chatId: Int64,
        topicId: MessageTopic?,
        isEnabled: Bool,
        interval: Foundation.TimeInterval = 4,
    ) {
        self.service = service
        self.chatId = chatId
        self.topicId = topicId
        self.isEnabled = isEnabled
        self.interval = interval
    }

    // MARK: Internal

    /// Call whenever the composer text changes to a non-empty value.
    func noteTyping() {
        guard isEnabled else { return }
        let now = Foundation.Date()
        if let lastSentAt, now.timeIntervalSince(lastSentAt) < interval { return }
        lastSentAt = now
        send(.chatActionTyping)
    }

    /// Call when the message is sent or the input is cleared. No-op if nothing was broadcast.
    func cancel() {
        guard isEnabled, lastSentAt != nil else { return }
        lastSentAt = nil
        send(.chatActionCancel)
    }

    // MARK: Private

    private let service: any TelegramService
    private let chatId: Int64
    private let topicId: MessageTopic?
    private let isEnabled: Bool
    private let interval: Foundation.TimeInterval
    private var lastSentAt: Foundation.Date?

    private func send(_ action: ChatAction) {
        Task { [service, chatId, topicId] in
            _ = try? await service.sendChatAction(
                action: action,
                businessConnectionId: nil,
                chatId: chatId,
                topicId: topicId,
            )
        }
    }
}
