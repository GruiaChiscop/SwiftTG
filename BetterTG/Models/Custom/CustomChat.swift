// CustomChat.swift

import SwiftUI
import TDLibKit

// MARK: - CustomChat

@Observable final class CustomChat {
    // MARK: Lifecycle

    init(
        chat: Chat,
        position: ChatPosition,
        unreadCount: Int,
        type: CustomChatType,
        lastMessage: Message? = nil,
        lastMessageSenderName: String? = nil,
        draftMessage: DraftMessage? = nil,
    ) {
        self.chat = chat
        self.notificationSettings = chat.notificationSettings
        self.lastReadInboxMessageId = chat.lastReadInboxMessageId
        self.lastReadOutboxMessageId = chat.lastReadOutboxMessageId
        self.isMarkedAsUnread = chat.isMarkedAsUnread
        self.position = position
        self.unreadCount = unreadCount
        self.type = type
        self.lastMessage = lastMessage
        self.lastMessageSenderName = lastMessageSenderName
        self.draftMessage = draftMessage
    }
    
    // MARK: Internal

    enum CustomChatType: Equatable, Hashable {
        case user(User)
        case supergroup(Supergroup)
        case group(BasicGroup)
        case bot(UserTypeBot)
    }

    enum ChatKind {
        case privateChat
        case bot
        case group
        case channel

        // MARK: Internal

        var title: String {
            switch self {
            case .privateChat: "Private chat"
            case .bot: "Bot"
            case .group: "Group"
            case .channel: "Channel"
            }
        }

        var systemImage: String? {
            switch self {
            case .privateChat: nil
            case .bot: "cpu.fill"
            case .group: "person.2.fill"
            case .channel: "megaphone.fill"
            }
        }
    }

    var chat: Chat
    var notificationSettings: ChatNotificationSettings
    var position: ChatPosition
    var unreadCount: Int
    var isMarkedAsUnread: Bool
    var lastReadInboxMessageId: Int64
    var lastReadOutboxMessageId: Int64
    var lastMessage: Message?
    var lastMessageSenderName: String?
    var draftMessage: DraftMessage?
    var type: CustomChatType

    var kind: ChatKind {
        switch type {
        case .user: .privateChat
        case .bot: .bot
        case .group: .group
        case .supergroup(let supergroup): supergroup.isChannel ? .channel : .group
        }
    }

    var showsLastMessageSender: Bool {
        switch type {
        case .group: true
        case .supergroup(let supergroup): !supergroup.isChannel
        case .bot, .user: false
        }
    }

    var isMuted: Bool { notificationSettings.muteFor > 0 }
    var hasUnreadMessages: Bool { unreadCount > 0 || isMarkedAsUnread }

    var actionPolicy: TelegramChatActionPolicy {
        TelegramChatActionPolicy(
            kind: ChatListItemKind(chat.type),
            membership: membershipStatus.map(ChatListMembership.init),
            canBeDeletedOnlyForSelf: chat.canBeDeletedOnlyForSelf,
            canBeDeletedForAllUsers: chat.canBeDeletedForAllUsers,
        )
    }
    
    var bot: UserTypeBot? {
        switch type {
        case .bot(let bot): bot
        default: nil
        }
    }
    
    var user: User? {
        switch type {
        case .user(let user): user
        default: nil
        }
    }
    
    var supergroup: Supergroup? {
        switch type {
        case .supergroup(let supergroup): supergroup
        default: nil
        }
    }
    
    var group: BasicGroup? {
        switch type {
        case .group(let group): group
        default: nil
        }
    }

    var adminRights: ChatAdministratorRights? {
        switch supergroup?.status {
        case .chatMemberStatusAdministrator(let chatMemberStatusAdministrator): chatMemberStatusAdministrator.rights
        default: nil
        }
    }
    
    var shouldShowProfileImage: Bool {
        switch type {
        case .bot, .user: false
        case .group, .supergroup: true
        }
    }
    
    var canPostMessages: Bool {
        if let supergroup {
            return telegramCanPostMessages(in: supergroup)
        }
        return true
    }

    // MARK: Private

    private var membershipStatus: ChatMemberStatus? {
        switch type {
        case .group(let group): group.status
        case .supergroup(let supergroup): supergroup.status
        case .bot, .user: nil
        }
    }
}

// MARK: Hashable

extension CustomChat: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(chat)
        hasher.combine(position)
        hasher.combine(unreadCount)
        hasher.combine(type)
        hasher.combine(lastMessage)
        hasher.combine(draftMessage)
    }
}

// MARK: Identifiable

extension CustomChat: Identifiable {
    var id: Int64 { chat.id }
}

// MARK: Equatable

extension CustomChat: Equatable {
    static func == (lhs: CustomChat, rhs: CustomChat) -> Bool {
        lhs.hashValue == rhs.hashValue
    }
}
