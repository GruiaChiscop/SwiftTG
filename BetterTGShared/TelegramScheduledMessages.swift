// TelegramScheduledMessages.swift

import Foundation
import TDLibKit

func telegramScheduledMessages(
    service: any TelegramService,
    chatId: Int64,
) async throws -> [Message] {
    let result = try await service.getChatScheduledMessages(chatId: chatId)
    return (result.messages ?? []).sorted { lhs, rhs in
        telegramScheduledMessageSortKey(lhs.schedulingState) < telegramScheduledMessageSortKey(rhs.schedulingState)
    }
}

func telegramScheduledMessageTimeDescription(_ state: MessageSchedulingState?) -> String {
    switch state {
    case .messageSchedulingStateSendAtDate(let value):
        telegramMessageDateDescription(value.sendDate)
    case .messageSchedulingStateSendWhenOnline:
        "Send When Online"
    case .messageSchedulingStateSendWhenVideoProcessed(let value):
        telegramMessageDateDescription(value.sendDate)
    case nil:
        ""
    }
}

/// "Send When Online" has no fixed date, so it sorts after every dated message - matching how
/// Telegram's own scheduled message list orders them.
private func telegramScheduledMessageSortKey(_ state: MessageSchedulingState?) -> Int {
    switch state {
    case .messageSchedulingStateSendAtDate(let value):
        value.sendDate
    case .messageSchedulingStateSendWhenVideoProcessed(let value):
        value.sendDate
    case .messageSchedulingStateSendWhenOnline, nil:
        .max
    }
}
