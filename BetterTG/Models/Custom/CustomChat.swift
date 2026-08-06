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
        showsMessageSender
    }

    var showsMessageSender: Bool {
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

    /// TDLib doesn't special-case the chat with yourself at all - `chat.title`/`chat.photo` are
    /// literally your own name/photo. Every real Telegram client detects and overrides this
    /// client-side; mirrors that using the same cache the identity-badge self-exclusion uses.
    @MainActor var isSavedMessages: Bool {
        telegramIsSavedMessages(entityUserId: user?.id, currentUserId: TelegramCurrentUserCache.shared.userId)
    }

    @MainActor var displayTitle: String {
        telegramDisplayTitle(title: chat.title, isSavedMessages: isSavedMessages)
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
    /// `CustomChat` is a reference type whose properties are already tracked individually by
    /// `@Observable` - the only consumer of this conformance (`.onChange(of: rootVM.folders)` in
    /// MainView.swift) just needs to know whether the *set of chat objects* changed, not whether
    /// any chat's content did. Hashing every nested TDLib field (recursively, including `chat`,
    /// `lastMessage`, etc.) was measured costing ~561ms during chat-list bootstrap via an
    /// xctrace Time Profiler capture, since each incrementally-appended chat re-triggers a full
    /// rehash of every chat already in its folder.
    func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}

// MARK: Identifiable

extension CustomChat: Identifiable {
    var id: Int64 { chat.id }
}

// MARK: Equatable

extension CustomChat: Equatable {
    static func == (lhs: CustomChat, rhs: CustomChat) -> Bool {
        lhs === rhs
    }
}

func conversationCommunityStatus(for chat: CustomChat) -> String {
    switch chat.type {
    case .bot, .user:
        ""
    case .group(let group):
        conversationGroupStatus(memberCount: group.memberCount)
    case .supergroup(let group):
        conversationSupergroupStatus(isChannel: group.isChannel, memberCount: group.memberCount)
    }
}

func conversationGroupStatus(memberCount: Int) -> String {
    guard memberCount > 0 else { return "Group" }
    return memberCount == 1 ? "1 member" : "\(memberCount.formatted()) members"
}

func conversationSupergroupStatus(isChannel: Bool, memberCount: Int) -> String {
    guard memberCount > 0 else { return isChannel ? "Channel" : "Group" }
    if isChannel {
        return memberCount == 1 ? "1 subscriber" : "\(memberCount.formatted()) subscribers"
    }
    return conversationGroupStatus(memberCount: memberCount)
}
