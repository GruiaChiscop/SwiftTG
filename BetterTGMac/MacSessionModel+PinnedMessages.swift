// MacSessionModel+PinnedMessages.swift

import Foundation
import TDLibKit

extension MacSessionModel {
    var currentPinnedMessage: Message? {
        pinnedMessages.first
    }

    func refreshPinnedMessages(for chatId: Int64? = nil) {
        guard let chatId = chatId ?? openedChatId else { return }
        pinnedMessagesTask?.cancel()
        pinnedMessagesGeneration &+= 1
        let generation = pinnedMessagesGeneration
        isLoadingPinnedMessages = true
        pinnedMessagesError = nil

        pinnedMessagesTask = Task { [weak self] in
            guard let self else { return }
            do {
                let messages = try await telegramPinnedMessages(service: service, chatId: chatId)
                guard !Task.isCancelled,
                      generation == pinnedMessagesGeneration,
                      openedChatId == chatId
                else { return }
                pinnedMessages = messages
                isLoadingPinnedMessages = false
            } catch is CancellationError {
                return
            } catch {
                guard generation == pinnedMessagesGeneration, openedChatId == chatId else { return }
                pinnedMessagesError = error.localizedDescription
                isLoadingPinnedMessages = false
            }
        }
    }
}
