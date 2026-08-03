// MacSessionModel+ScheduledMessages.swift

import Foundation
import TDLibKit

extension MacSessionModel {
    func refreshScheduledMessages(for chatId: Int64? = nil) {
        guard let chatId = chatId ?? openedChatId else { return }
        scheduledMessagesTask?.cancel()
        scheduledMessagesGeneration &+= 1
        let generation = scheduledMessagesGeneration
        isLoadingScheduledMessages = true
        scheduledMessagesError = nil

        scheduledMessagesTask = Task { [weak self] in
            guard let self else { return }
            do {
                let messages = try await telegramScheduledMessages(service: service, chatId: chatId)
                guard !Task.isCancelled,
                      generation == scheduledMessagesGeneration,
                      openedChatId == chatId
                else { return }
                scheduledMessages = messages
                isLoadingScheduledMessages = false
            } catch is CancellationError {
                return
            } catch {
                guard generation == scheduledMessagesGeneration, openedChatId == chatId else { return }
                scheduledMessagesError = telegramErrorDescription(error)
                isLoadingScheduledMessages = false
            }
        }
    }

    func sendScheduledMessageNow(_ message: Message) {
        performScheduledMessageAction(failureMessage: "Message couldn't be sent") {
            _ = try await self.service.editMessageSchedulingState(
                chatId: message.chatId,
                messageId: message.id,
                schedulingState: nil,
            )
        }
    }

    func rescheduleMessage(_ message: Message, to schedulingState: MessageSchedulingState) {
        performScheduledMessageAction(failureMessage: "Message couldn't be rescheduled") {
            _ = try await self.service.editMessageSchedulingState(
                chatId: message.chatId,
                messageId: message.id,
                schedulingState: schedulingState,
            )
        }
    }

    func deleteScheduledMessage(_ message: Message) {
        performScheduledMessageAction(failureMessage: "Message couldn't be deleted") {
            _ = try await self.service.deleteMessages(
                chatId: message.chatId,
                messageIds: [message.id],
                revoke: true,
            )
        }
    }

    // MARK: Private

    private func performScheduledMessageAction(
        failureMessage: String,
        _ action: @escaping @MainActor () async throws -> Void,
    ) {
        let chatId = openedChatId
        scheduledMessagesError = nil
        Task {
            do {
                try await action()
                refreshScheduledMessages(for: chatId)
            } catch {
                scheduledMessagesError = "\(failureMessage): \(telegramErrorDescription(error))"
            }
        }
    }
}
