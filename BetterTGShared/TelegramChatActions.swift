// TelegramChatActions.swift

import TDLibKit

/// Chat-list actions shared between the iOS (RootVM) and macOS (MacSessionModel)
/// view models, which wrap chats in different types but call the same TDLib flow.
enum TelegramChatActions {
    static func toggleRead(
        service: any TelegramService,
        chatId: Int64,
        unreadCount: Int,
        lastMessageId: Int64?,
        isMarkedAsUnread: Bool,
    ) async {
        if unreadCount > 0 {
            guard let lastMessageId else { return }
            _ = try? await service.viewMessages(
                chatId: chatId,
                forceRead: true,
                messageIds: [lastMessageId],
                source: .messageSourceChatList,
            )
        } else {
            _ = try? await service.toggleChatIsMarkedAsUnread(
                chatId: chatId,
                isMarkedAsUnread: !isMarkedAsUnread,
            )
        }
    }

    static func togglePinned(
        service: any TelegramService,
        chatId: Int64,
        chatList: ChatList,
        newIsPinned: Bool,
    ) async {
        _ = try? await service.toggleChatIsPinned(
            chatId: chatId,
            chatList: chatList,
            isPinned: newIsPinned,
        )
    }

    static func toggleArchived(
        service: any TelegramService,
        chatId: Int64,
        isCurrentlyArchived: Bool,
    ) async {
        _ = try? await service.addChatToList(
            chatId: chatId,
            chatList: isCurrentlyArchived ? .chatListMain : .chatListArchive,
        )
    }

    static func deleteChatHistory(
        service: any TelegramService,
        chatId: Int64,
        forEveryone: Bool,
    ) async {
        _ = try? await service.deleteChatHistory(
            chatId: chatId,
            removeFromChatList: true,
            revoke: forEveryone,
        )
    }

    static func setMuteDuration(
        service: any TelegramService,
        chatId: Int64,
        duration: Int,
        current: ChatNotificationSettings,
    ) async {
        let settings = ChatNotificationSettings(
            disableMentionNotifications: current.disableMentionNotifications,
            disablePinnedMessageNotifications: current.disablePinnedMessageNotifications,
            muteFor: duration,
            muteStories: current.muteStories,
            showPreview: current.showPreview,
            showStoryPoster: current.showStoryPoster,
            soundId: current.soundId,
            storySoundId: current.storySoundId,
            useDefaultDisableMentionNotifications: current.useDefaultDisableMentionNotifications,
            useDefaultDisablePinnedMessageNotifications: current.useDefaultDisablePinnedMessageNotifications,
            useDefaultMuteFor: false,
            useDefaultMuteStories: current.useDefaultMuteStories,
            useDefaultShowPreview: current.useDefaultShowPreview,
            useDefaultShowStoryPoster: current.useDefaultShowStoryPoster,
            useDefaultSound: current.useDefaultSound,
            useDefaultStorySound: current.useDefaultStorySound,
        )
        _ = try? await service.setChatNotificationSettings(
            chatId: chatId,
            notificationSettings: settings,
        )
    }
}
