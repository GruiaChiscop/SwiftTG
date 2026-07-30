// ChatVM+PinnedMessages.swift

import Foundation
import TDLibKit

extension ChatVM {
    var currentPinnedMessage: Message? {
        pinnedMessages.first
    }

    func refreshPinnedMessages() {
        pinnedMessagesTask?.cancel()
        pinnedMessagesGeneration += 1
        let generation = pinnedMessagesGeneration
        isLoadingPinnedMessages = true
        pinnedMessagesError = nil

        pinnedMessagesTask = Task { [weak self] in
            guard let self else { return }
            do {
                let messages = try await telegramPinnedMessages(
                    service: service,
                    chatId: customChat.chat.id,
                )
                guard !Task.isCancelled, generation == pinnedMessagesGeneration else { return }
                pinnedMessages = messages
                isLoadingPinnedMessages = false
            } catch is CancellationError {
                return
            } catch {
                guard generation == pinnedMessagesGeneration else { return }
                pinnedMessagesError = error.localizedDescription
                isLoadingPinnedMessages = false
            }
        }
    }
}
