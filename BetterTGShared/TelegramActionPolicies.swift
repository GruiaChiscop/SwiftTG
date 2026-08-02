// TelegramActionPolicies.swift

import TDLibKit

// MARK: - TelegramChatActionPolicy

struct TelegramChatActionPolicy: Sendable, Equatable {
    let kind: ChatListItemKind
    let membership: ChatListMembership?
    let canBeDeletedOnlyForSelf: Bool
    let canBeDeletedForAllUsers: Bool

    var canClearHistory: Bool {
        canBeDeletedOnlyForSelf || canBeDeletedForAllUsers
    }

    var canLeave: Bool {
        membership == .member
    }

    var canDeleteCommunity: Bool {
        membership == .creator && canBeDeletedForAllUsers
    }

    var canDeleteChat: Bool {
        switch kind {
        case .privateChat, .secretChat: canClearHistory
        case .channel, .group: canDeleteCommunity || (membership != .member && canClearHistory)
        }
    }

    var deleteActionTitle: String {
        switch kind {
        case .group: "Delete Group"
        case .channel: "Delete Channel"
        case .privateChat, .secretChat: "Delete Chat"
        }
    }

    var leaveActionTitle: String? {
        guard canLeave else { return nil }
        return kind == .channel ? "Leave Channel" : "Leave Group"
    }
}

// MARK: - TelegramMutePreset

enum TelegramMutePreset: CaseIterable, Identifiable, Sendable {
    case oneHour
    case eightHours
    case twoDays
    case forever

    // MARK: Internal

    var id: Self { self }

    var duration: Int {
        switch self {
        case .oneHour: 60 * 60
        case .eightHours: 8 * 60 * 60
        case .twoDays: 2 * 24 * 60 * 60
        case .forever: Int(Int32.max)
        }
    }

    var title: String {
        switch self {
        case .oneHour: "Mute for 1 hour"
        case .eightHours: "Mute for 8 hours"
        case .twoDays: "Mute for 2 days"
        case .forever: "Mute forever"
        }
    }
}

// MARK: - TelegramMessageActions

enum TelegramMessageActions {
    static func setPollAnswer(
        service: any TelegramService,
        message: Message,
        optionPositions: [Int],
    ) async throws {
        _ = try await service.setPollAnswer(
            chatId: message.chatId,
            messageId: message.id,
            optionIds: optionPositions,
        )
        if let refreshedMessage = try? await service.getMessage(chatId: message.chatId, messageId: message.id) {
            service.mergeMessages(chatId: message.chatId, messages: [refreshedMessage])
        }
    }

    static func toggleReaction(
        service: any TelegramService,
        message: Message,
        reaction: ReactionType,
    ) async throws {
        let isChosen = telegramReactionCanBeRemoved(reaction)
            && message.interactionInfo?.reactions?.reactions.contains {
                $0.type == reaction && $0.isChosen
            } == true
        _ =
            if isChosen {
                try await service.removeMessageReaction(
                    chatId: message.chatId,
                    messageId: message.id,
                    reactionType: reaction,
                )
            } else {
                try await service.addMessageReaction(
                    chatId: message.chatId,
                    isBig: false,
                    messageId: message.id,
                    reactionType: reaction,
                    updateRecentReactions: true,
                )
            }
    }

    static func togglePinned(service: any TelegramService, message: Message) async throws {
        _ =
            if message.isPinned {
                try await service.unpinChatMessage(chatId: message.chatId, messageId: message.id)
            } else {
                try await service.pinChatMessage(
                    chatId: message.chatId,
                    disableNotification: false,
                    messageId: message.id,
                    onlyForSelf: false,
                )
            }
    }

    static func delete(
        service: any TelegramService,
        chatId: Int64,
        messageIds: [Int64],
        forEveryone: Bool,
    ) async throws {
        _ = try await service.deleteMessages(
            chatId: chatId,
            messageIds: messageIds,
            revoke: forEveryone,
        )
    }

    @discardableResult static func forward(
        service: any TelegramService,
        messageIds: [Int64],
        fromChatId: Int64,
        toChatId: Int64,
    ) async throws -> Messages {
        try await service.forwardMessages(
            chatId: toChatId,
            fromChatId: fromChatId,
            messageIds: messageIds.sorted(),
            options: nil,
            removeCaption: false,
            sendCopy: false,
            topicId: nil,
        )
    }
}
