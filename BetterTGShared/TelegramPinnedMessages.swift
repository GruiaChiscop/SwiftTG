// TelegramPinnedMessages.swift

import TDLibKit

func telegramPinnedMessages(
    service: any TelegramService,
    chatId: Int64,
) async throws -> [Message] {
    var fromMessageId: Int64 = 0
    var messages = [Message]()
    var seenMessageIds = Set<Int64>()

    while true {
        let result = try await service.searchChatMessages(
            chatId: chatId,
            filter: .searchMessagesFilterPinned,
            fromMessageId: fromMessageId,
            limit: 100,
            offset: 0,
            query: "",
            senderId: nil,
            topicId: nil,
        )

        for message in result.messages where seenMessageIds.insert(message.id).inserted {
            messages.append(message)
        }

        let nextFromMessageId = result.nextFromMessageId
        guard nextFromMessageId != 0,
              nextFromMessageId != fromMessageId,
              !result.messages.isEmpty,
              result.totalCount < 0 || messages.count < result.totalCount
        else { break }
        fromMessageId = nextFromMessageId
    }

    return messages
}
