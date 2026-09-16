// MacSessionModel+SendAs.swift

import Foundation
import TDLibKit

extension MacSessionModel {
    /// Loads the identities the user may send messages in `chatId` as, plus the one currently
    /// selected - mirrors iOS's `ChatVM.sendAsIdentities()`/`startSendAsObservation()`. Only
    /// groups can have more than one, so private chats, bots and channels skip the round trip.
    func refreshSendAsState(for chatId: Int64, isGroupChat: Bool) {
        sendAsTask?.cancel()
        sendAsCandidates = []
        sendAsIdentity = nil
        guard isGroupChat else { return }
        sendAsTask = Task { [weak self] in
            guard let self else { return }
            async let candidates = (try? service.getChatAvailableMessageSenders(chatId: chatId))?.senders
                .map(\.sender) ?? []
            async let chat = try? service.getChat(chatId: chatId)
            let (resolvedCandidates, resolvedChat) = await (candidates, chat)
            guard !Task.isCancelled, openedChatId == chatId else { return }
            sendAsCandidates = resolvedCandidates
            sendAsIdentity = resolvedChat?.messageSenderId
        }
    }

    func setSendAsIdentity(_ sender: MessageSender) {
        guard let chatId = openedChatId else { return }
        sendAsIdentity = sender
        Task { _ = try? await service.setChatMessageSender(chatId: chatId, messageSenderId: sender) }
    }

    func handleSendAsUpdate(_ update: Update) {
        guard case .updateChatMessageSender(let value) = update, value.chatId == openedChatId else { return }
        sendAsIdentity = value.messageSenderId
    }
}
