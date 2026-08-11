// TelegramMediaSendPermission.swift

import TDLibKit

enum TelegramMediaSendPermission: Equatable, Sendable {
    case allowed
    case restricted

    // MARK: Internal

    static func resolve(
        service: any TelegramService,
        chatID: Int64,
    ) async throws -> Self {
        let chat = try await service.getChat(chatId: chatID)
        let isAllowed: Bool
        switch chat.type {
        case .chatTypeBasicGroup(let type):
            let group = try await service.getBasicGroup(basicGroupId: type.basicGroupId)
            isAllowed = allowsSending(
                defaultPermissions: chat.permissions,
                status: group.status,
                isChannel: false,
            )
        case .chatTypeSupergroup(let type):
            let supergroup = try await service.getSupergroup(supergroupId: type.supergroupId)
            isAllowed = allowsSending(
                defaultPermissions: chat.permissions,
                status: supergroup.status,
                isChannel: supergroup.isChannel,
            )
        case .chatTypePrivate, .chatTypeSecret:
            isAllowed = chat.permissions.canSendOtherMessages
        }
        return isAllowed ? .allowed : .restricted
    }

    static func allowsSending(
        defaultPermissions: ChatPermissions,
        status: ChatMemberStatus,
        isChannel: Bool,
    ) -> Bool {
        switch status {
        case .chatMemberStatusCreator:
            true
        case .chatMemberStatusAdministrator(let administrator):
            isChannel ? administrator.rights.canPostMessages : true
        case .chatMemberStatusMember:
            !isChannel && defaultPermissions.canSendOtherMessages
        case .chatMemberStatusRestricted(let restricted):
            !isChannel && restricted.isMember && restricted.permissions.canSendOtherMessages
        case .chatMemberStatusBanned, .chatMemberStatusLeft:
            false
        }
    }

    static func shouldReload(after update: Update, chatID: Int64) -> Bool {
        switch update {
        case .updateChatPermissions(let value):
            value.chatId == chatID
        case .updateBasicGroup, .updateSupergroup:
            true
        default:
            false
        }
    }

    func message(for tab: TelegramMediaPickerTab) -> String? {
        guard self == .restricted else { return nil }
        return switch tab {
        case .stickers: "You don't have permission to send stickers in this chat."
        case .gifs: "You don't have permission to send GIFs in this chat."
        }
    }
}
