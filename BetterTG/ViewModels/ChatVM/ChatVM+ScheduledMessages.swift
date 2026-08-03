// ChatVM+ScheduledMessages.swift

import Foundation
import TDLibKit

extension ChatVM {
    func refreshScheduledMessages() {
        scheduledMessagesTask?.cancel()
        scheduledMessagesGeneration += 1
        let generation = scheduledMessagesGeneration
        isLoadingScheduledMessages = true
        scheduledMessagesError = nil

        scheduledMessagesTask = Task { [weak self] in
            guard let self else { return }
            do {
                let messages = try await telegramScheduledMessages(service: service, chatId: customChat.chat.id)
                guard !Task.isCancelled, generation == scheduledMessagesGeneration else { return }
                scheduledMessages = messages
                isLoadingScheduledMessages = false
            } catch is CancellationError {
                return
            } catch {
                guard generation == scheduledMessagesGeneration else { return }
                scheduledMessagesError = telegramErrorDescription(error)
                isLoadingScheduledMessages = false
            }
        }
    }

    func sendScheduledMessageNow(_ message: Message) {
        performScheduledMessageAction(failureMessage: "Message couldn't be sent") {
            _ = try await self.service.editMessageSchedulingState(
                chatId: self.customChat.chat.id,
                messageId: message.id,
                schedulingState: nil,
            )
        }
    }

    func rescheduleMessage(_ message: Message, to schedulingState: MessageSchedulingState) {
        performScheduledMessageAction(failureMessage: "Message couldn't be rescheduled") {
            _ = try await self.service.editMessageSchedulingState(
                chatId: self.customChat.chat.id,
                messageId: message.id,
                schedulingState: schedulingState,
            )
        }
    }

    func deleteScheduledMessage(_ message: Message) {
        performScheduledMessageAction(failureMessage: "Message couldn't be deleted") {
            _ = try await self.service.deleteMessages(
                chatId: self.customChat.chat.id,
                messageIds: [message.id],
                revoke: true,
            )
        }
    }

    // MARK: Private

    private func performScheduledMessageAction(
        failureMessage: String,
        _ action: @escaping @Sendable () async throws -> Void,
    ) {
        scheduledMessagesError = nil
        Task { [weak self] in
            guard let self else { return }
            do {
                try await action()
                guard !Task.isCancelled else { return }
                refreshScheduledMessages()
            } catch {
                guard !Task.isCancelled else { return }
                scheduledMessagesError = "\(failureMessage): \(telegramErrorDescription(error))"
            }
        }
    }
}
