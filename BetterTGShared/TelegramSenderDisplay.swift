// TelegramSenderDisplay.swift

import TDLibKit

func telegramUserDisplayName(_ user: User) -> String {
    "\(user.firstName) \(user.lastName)".trimmingCharacters(in: .whitespaces)
}

// MARK: - TelegramSenderName

/// Resolves the display name for a message sender, shared between RootVM (iOS)
/// and MacSessionModel (macOS), which otherwise ran the same user/chat lookup twice.
enum TelegramSenderName {
    static func displayName(service: any TelegramService, senderId: MessageSender) async -> String? {
        switch senderId {
        case .messageSenderUser(let sender):
            guard let user = try? await service.getUser(userId: sender.userId) else { return nil }
            return telegramUserDisplayName(user)
        case .messageSenderChat(let sender):
            return try? await service.getChat(chatId: sender.chatId).title
        }
    }
}

// MARK: - TelegramMessageOrigin

/// Resolves the "Forwarded from" label for a message origin, shared between
/// ChatVM.getForwardedFrom (iOS) and MacSessionModel.loadForwardedFrom (macOS).
enum TelegramMessageOrigin {
    static func displayName(service: any TelegramService, origin: MessageOrigin) async -> String? {
        switch origin {
        case .messageOriginChat(let chat):
            let title = try? await service.getChat(chatId: chat.senderChatId).title
            return title.map { chat.authorSignature.isEmpty ? $0 : "\($0) (\(chat.authorSignature))" }
                ?? (chat.authorSignature.isEmpty ? nil : chat.authorSignature)
        case .messageOriginChannel(let channel):
            let title = try? await service.getChat(chatId: channel.chatId).title
            return title.map { channel.authorSignature.isEmpty ? $0 : "\($0) (\(channel.authorSignature))" }
                ?? (channel.authorSignature.isEmpty ? nil : channel.authorSignature)
        case .messageOriginHiddenUser(let user):
            return user.senderName
        case .messageOriginUser(let user):
            return try? await service.getUser(userId: user.senderUserId).firstName
        }
    }
}
