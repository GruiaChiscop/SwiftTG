// ChatVM+SendAs.swift

import Combine
import Foundation
@preconcurrency import TDLibKit

extension ChatVM {
    /// Seeds `sendAsIdentity` from the chat snapshot and keeps it live from `updateChatMessageSender`.
    func startSendAsObservation() {
        sendAsIdentity = customChat.chat.messageSenderId
        let chatId = customChat.chat.id
        service.updatePublisher
            .compactMap { update -> UpdateChatMessageSender? in
                guard case .updateChatMessageSender(let value) = update, value.chatId == chatId else { return nil }
                return value
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                Task { @MainActor in self?.sendAsIdentity = value.messageSenderId }
            }
            .store(in: &cancellables)
    }

    /// Identities the current user may send messages in this chat as - self, plus any channel
    /// they administer that's linked to this group. More than one means the composer should offer
    /// a "Send As" choice, mirroring `videoChatJoinIdentities()`.
    func sendAsIdentities() async -> [MessageSender] {
        await (try? service.getChatAvailableMessageSenders(chatId: customChat.chat.id))?.senders.map(\.sender) ?? []
    }

    func setSendAsIdentity(_ sender: MessageSender) async {
        sendAsIdentity = sender
        _ = try? await service.setChatMessageSender(chatId: customChat.chat.id, messageSenderId: sender)
    }
}
