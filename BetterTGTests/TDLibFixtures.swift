// TDLibFixtures.swift

import TDLibKit

enum TDLibFixtures {
    // MARK: Internal

    static func file(
        id: Int,
        downloadedSize: Int64,
        isDownloadingCompleted: Bool = false,
        path: String = "",
    ) -> File {
        File(
            expectedSize: 100,
            id: id,
            local: LocalFile(
                canBeDeleted: true,
                canBeDownloaded: true,
                downloadOffset: 0,
                downloadedPrefixSize: downloadedSize,
                downloadedSize: downloadedSize,
                isDownloadingActive: !isDownloadingCompleted,
                isDownloadingCompleted: isDownloadingCompleted,
                path: path,
            ),
            remote: RemoteFile(
                id: "remote-\(id)",
                isUploadingActive: false,
                isUploadingCompleted: true,
                uniqueId: "unique-\(id)",
                uploadedSize: 100,
            ),
            size: 100,
        )
    }

    static func chat(
        id: Int64,
        order: Int64,
        unreadCount: Int = 0,
        list: ChatList = .chatListMain,
        lastMessage: Message? = nil,
    ) -> Chat {
        Chat(
            accentColorId: 0,
            actionBar: nil,
            availableReactions: .chatAvailableReactionsAll(.init(maxReactionCount: 1)),
            background: nil,
            backgroundCustomEmojiId: 0,
            blockList: nil,
            businessBotManageBar: nil,
            canBeDeletedForAllUsers: true,
            canBeDeletedOnlyForSelf: true,
            canBeReported: false,
            chatLists: [list],
            clientData: "",
            defaultDisableNotification: false,
            draftMessage: nil,
            emojiStatus: nil,
            hasProtectedContent: false,
            hasScheduledMessages: false,
            id: id,
            isMarkedAsUnread: false,
            isTranslatable: false,
            lastMessage: lastMessage,
            lastReadInboxMessageId: 0,
            lastReadOutboxMessageId: 0,
            messageAutoDeleteTime: 0,
            messageSenderId: nil,
            notificationSettings: notificationSettings,
            pendingJoinRequests: nil,
            permissions: permissions,
            photo: nil,
            positions: [position(order: order, list: list)],
            profileAccentColorId: -1,
            profileBackgroundCustomEmojiId: 0,
            replyMarkupMessageId: 0,
            theme: nil,
            title: "Chat \(id)",
            type: .chatTypePrivate(.init(userId: id)),
            unreadCount: unreadCount,
            unreadMentionCount: 0,
            unreadPollVoteCount: 0,
            unreadReactionCount: 0,
            upgradedGiftColors: nil,
            videoChat: .init(defaultParticipantId: nil, groupCallId: 0, hasParticipants: false),
            viewAsTopics: false,
        )
    }

    static func message(
        id: Int64,
        chatId: Int64,
        date: Int,
        text: String = "Message",
        editDate: Int = 0,
        isOutgoing: Bool = false,
        sendingState: MessageSendingState? = nil,
    ) -> Message {
        Message(
            authorSignature: "",
            autoDeleteIn: 0,
            canBeSaved: true,
            chatId: chatId,
            containsUnreadMention: false,
            containsUnreadPollVotes: false,
            content: .messageText(.init(
                linkPreview: nil,
                linkPreviewOptions: nil,
                text: .init(entities: [], text: text),
            )),
            date: date,
            editDate: editDate,
            effectId: 0,
            ephemeralMessageId: 0,
            factCheck: nil,
            forwardInfo: nil,
            guestBotCallerId: nil,
            hasTimestampedMedia: false,
            id: id,
            importInfo: nil,
            interactionInfo: nil,
            isChannelPost: false,
            isFromOffline: false,
            isOutgoing: isOutgoing,
            isPaidGramSuggestedPost: false,
            isPaidStarSuggestedPost: false,
            isPinned: false,
            mediaAlbumId: 0,
            paidMessageStarCount: 0,
            receiverId: nil,
            replyMarkup: nil,
            replyTo: nil,
            restrictionInfo: nil,
            schedulingState: nil,
            selfDestructIn: 0,
            selfDestructType: nil,
            senderBoostCount: 0,
            senderBusinessBotUserId: 0,
            senderId: .messageSenderUser(.init(userId: 1)),
            senderTag: "",
            sendingState: sendingState,
            suggestedPostInfo: nil,
            summaryLanguageCode: "",
            topicId: nil,
            unreadReactions: [],
            viaBotUserId: 0,
        )
    }

    static func position(order: Int64, list: ChatList = .chatListMain) -> ChatPosition {
        ChatPosition(isPinned: false, list: list, order: TdInt64(order), source: nil)
    }

    // MARK: Private

    private static let notificationSettings = ChatNotificationSettings(
        disableMentionNotifications: false,
        disablePinnedMessageNotifications: false,
        muteFor: 0,
        muteStories: false,
        showPreview: true,
        showStoryPoster: true,
        soundId: 0,
        storySoundId: 0,
        useDefaultDisableMentionNotifications: true,
        useDefaultDisablePinnedMessageNotifications: true,
        useDefaultMuteFor: true,
        useDefaultMuteStories: true,
        useDefaultShowPreview: true,
        useDefaultShowStoryPoster: true,
        useDefaultSound: true,
        useDefaultStorySound: true,
    )

    private static let permissions = ChatPermissions(
        canAddLinkPreviews: true,
        canChangeInfo: false,
        canCreateTopics: false,
        canEditTag: false,
        canInviteUsers: false,
        canPinMessages: false,
        canReactToMessages: true,
        canSendAudios: true,
        canSendBasicMessages: true,
        canSendDocuments: true,
        canSendOtherMessages: true,
        canSendPhotos: true,
        canSendPolls: true,
        canSendVideoNotes: true,
        canSendVideos: true,
        canSendVoiceNotes: true,
    )
}
