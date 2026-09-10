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

    static func clearChatHistory(
        service: any TelegramService,
        chatId: Int64,
        forEveryone: Bool,
    ) async {
        _ = try? await service.deleteChatHistory(
            chatId: chatId,
            removeFromChatList: false,
            revoke: forEveryone,
        )
    }

    static func leaveChat(
        service: any TelegramService,
        chatId: Int64,
    ) async {
        guard await (try? service.leaveChat(chatId: chatId)) != nil else { return }
        _ = try? await service.deleteChatHistory(
            chatId: chatId,
            removeFromChatList: true,
            revoke: false,
        )
    }

    static func deleteCommunity(
        service: any TelegramService,
        chatId: Int64,
    ) async {
        _ = try? await service.deleteChat(chatId: chatId)
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

    /// Returns the settings that were sent, so a caller holding a local snapshot can keep it in
    /// sync for a subsequent toggle.
    @discardableResult static func setShowPreview(
        service: any TelegramService,
        chatId: Int64,
        showPreview: Bool,
        current: ChatNotificationSettings,
    ) async -> ChatNotificationSettings {
        let updated = overriding(current, showPreview: showPreview)
        _ = try? await service.setChatNotificationSettings(chatId: chatId, notificationSettings: updated)
        return updated
    }

    @discardableResult static func setMuteStories(
        service: any TelegramService,
        chatId: Int64,
        muteStories: Bool,
        current: ChatNotificationSettings,
    ) async -> ChatNotificationSettings {
        let updated = overriding(current, muteStories: muteStories)
        _ = try? await service.setChatNotificationSettings(chatId: chatId, notificationSettings: updated)
        return updated
    }

    /// TDLib's `ChatNotificationSettings` is immutable; rebuild it carrying every field through,
    /// overriding only the one being changed and clearing its matching `useDefault*` flag.
    private static func overriding(
        _ c: ChatNotificationSettings,
        showPreview: Bool? = nil,
        muteStories: Bool? = nil,
    ) -> ChatNotificationSettings {
        ChatNotificationSettings(
            disableMentionNotifications: c.disableMentionNotifications,
            disablePinnedMessageNotifications: c.disablePinnedMessageNotifications,
            muteFor: c.muteFor,
            muteStories: muteStories ?? c.muteStories,
            showPreview: showPreview ?? c.showPreview,
            showStoryPoster: c.showStoryPoster,
            soundId: c.soundId,
            storySoundId: c.storySoundId,
            useDefaultDisableMentionNotifications: c.useDefaultDisableMentionNotifications,
            useDefaultDisablePinnedMessageNotifications: c.useDefaultDisablePinnedMessageNotifications,
            useDefaultMuteFor: c.useDefaultMuteFor,
            useDefaultMuteStories: muteStories == nil ? c.useDefaultMuteStories : false,
            useDefaultShowPreview: showPreview == nil ? c.useDefaultShowPreview : false,
            useDefaultShowStoryPoster: c.useDefaultShowStoryPoster,
            useDefaultSound: c.useDefaultSound,
            useDefaultStorySound: c.useDefaultStorySound,
        )
    }

    /// `useDefault: true` means "use this chat's scope default sound", matching
    /// `ChatNotificationSettings.useDefaultSound`'s own meaning - `soundId` is ignored by TDLib in
    /// that case, so it's fine to just carry `current.soundId` through unchanged.
    static func setSoundId(
        service: any TelegramService,
        chatId: Int64,
        soundId: TdInt64,
        useDefault: Bool,
        current: ChatNotificationSettings,
    ) async {
        let settings = ChatNotificationSettings(
            disableMentionNotifications: current.disableMentionNotifications,
            disablePinnedMessageNotifications: current.disablePinnedMessageNotifications,
            muteFor: current.muteFor,
            muteStories: current.muteStories,
            showPreview: current.showPreview,
            showStoryPoster: current.showStoryPoster,
            soundId: useDefault ? current.soundId : soundId,
            storySoundId: current.storySoundId,
            useDefaultDisableMentionNotifications: current.useDefaultDisableMentionNotifications,
            useDefaultDisablePinnedMessageNotifications: current.useDefaultDisablePinnedMessageNotifications,
            useDefaultMuteFor: current.useDefaultMuteFor,
            useDefaultMuteStories: current.useDefaultMuteStories,
            useDefaultShowPreview: current.useDefaultShowPreview,
            useDefaultShowStoryPoster: current.useDefaultShowStoryPoster,
            useDefaultSound: useDefault,
            useDefaultStorySound: current.useDefaultStorySound,
        )
        _ = try? await service.setChatNotificationSettings(
            chatId: chatId,
            notificationSettings: settings,
        )
        await TelegramNotificationSoundCache.refreshChat(
            chatId: chatId,
            useDefault: useDefault,
            soundId: soundId,
            service: service,
        )
    }
}
