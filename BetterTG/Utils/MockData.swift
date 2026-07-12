// MockData.swift

#if DEBUG
import SwiftUI
import TDLibKit

enum MockData {
    static var isEnabled = false

    static func install() {
        isEnabled = true
        let rootVM = RootVM.shared
        // Stop reacting to the real TDLib client's authorization-state updates,
        // otherwise it flips `loggedIn` back to false once it reports
        // authorizationStateWaitPhoneNumber shortly after launch.
        rootVM.cancellables.removeAll()
        rootVM.folders = [makeMainFolder(), makeWorkFolder()]
        rootVM.archive = CustomFolder(chats: [], type: .archive)
        rootVM.loggedIn = true
    }

    static func makeMessages(chatId: Int64, otherUser: User) -> [CustomMessage] {
        let now = Int(Date.now.timeIntervalSince1970)
        let texts: [(fromOther: Bool, text: String)] = [
            (true, "Salut! Ce faci?"),
            (true, "Ai văzut mesajul de ieri?"),
            (false, "Da, am văzut, îmi pare rău de întârziere"),
            (false, "Sunt puțin ocupat azi"),
            (false, "Dar putem vorbi diseară"),
            (true, "Perfect, sună-mă atunci"),
            (true, "Nu uita de întâlnirea de mâine"),
            (false, "Am notat, mulțumesc de reminder"),
        ]
        return texts.enumerated().map { index, entry in
            let message = Message(
                authorSignature: "",
                autoDeleteIn: 0,
                canBeSaved: true,
                chatId: chatId,
                containsUnreadMention: false,
                containsUnreadPollVotes: false,
                content: .messageText(MessageText(
                    linkPreview: nil,
                    linkPreviewOptions: nil,
                    text: FormattedText(entities: [], text: entry.text),
                )),
                date: now - (texts.count - index) * 300,
                editDate: 0,
                effectId: 0,
                factCheck: nil,
                forwardInfo: nil,
                guestBotCallerId: nil,
                hasTimestampedMedia: false,
                id: Int64(index + 1),
                importInfo: nil,
                interactionInfo: nil,
                isChannelPost: false,
                isFromOffline: false,
                isOutgoing: !entry.fromOther,
                isPaidStarSuggestedPost: false,
                isPaidTonSuggestedPost: false,
                isPinned: false,
                mediaAlbumId: 0,
                paidMessageStarCount: 0,
                replyMarkup: nil,
                replyTo: nil,
                restrictionInfo: nil,
                schedulingState: nil,
                selfDestructIn: 0,
                selfDestructType: nil,
                senderBoostCount: 0,
                senderBusinessBotUserId: 0,
                senderId: .messageSenderUser(MessageSenderUser(userId: entry.fromOther ? otherUser.id : 0)),
                senderTag: "",
                sendingState: nil,
                suggestedPostInfo: nil,
                summaryLanguageCode: "",
                topicId: nil,
                unreadReactions: [],
                viaBotUserId: 0,
            )
            let customMessage = CustomMessage(message: message, properties: .default)
            customMessage.formattedText = FormattedText(entities: [], text: entry.text)
            if entry.fromOther {
                customMessage.senderUser = otherUser
            }
            return customMessage
        }
    }

    static func makeMainFolder() -> CustomFolder {
        CustomFolder(
            chats: [
                makeCustomChat(id: 1, firstName: "Ana", lastName: "Popescu", isPinned: true, unreadCount: 3),
                makeCustomChat(id: 2, firstName: "Mihai", lastName: "Ionescu", isMarkedAsUnread: true),
                makeCustomChat(id: 3, firstName: "Elena", lastName: "Georgescu", unreadCount: 12),
                makeCustomChat(id: 4, firstName: "Test", lastName: "User"),
                makeCustomChat(id: 5, firstName: "Radu", lastName: "Stan"),
                makeCustomChat(id: 6, firstName: "Ioana", lastName: "Vasile", isPinned: true),
                makeCustomChat(id: 7, firstName: "Cristian", lastName: "Marin"),
            ],
            type: .main,
        )
    }

    static func makeWorkFolder() -> CustomFolder {
        CustomFolder(
            chats: [
                makeCustomChat(id: 8, firstName: "Work", lastName: "Group", unreadCount: 5),
                makeCustomChat(id: 9, firstName: "Boss", lastName: ""),
            ],
            type: .folder(
                ChatFolderInfo(
                    colorId: 0,
                    hasMyInviteLinks: false,
                    icon: ChatFolderIcon(name: "Work"),
                    id: 100,
                    isShareable: false,
                    name: ChatFolderName(animateCustomEmoji: false, text: FormattedText(entities: [], text: "Work")),
                ),
                ChatFolder(
                    colorId: 0,
                    excludeArchived: false,
                    excludeMuted: false,
                    excludeRead: false,
                    excludedChatIds: [],
                    icon: nil,
                    includeBots: false,
                    includeChannels: false,
                    includeContacts: false,
                    includeGroups: false,
                    includeNonContacts: false,
                    includedChatIds: [],
                    isShareable: false,
                    name: ChatFolderName(animateCustomEmoji: false, text: FormattedText(entities: [], text: "Work")),
                    pinnedChatIds: [],
                ),
            ),
        )
    }

    static func makeCustomChat(
        id: Int64,
        firstName: String,
        lastName: String = "",
        isPinned: Bool = false,
        isMarkedAsUnread: Bool = false,
        unreadCount: Int = 0,
    ) -> CustomChat {
        let user = makeUser(id: id, firstName: firstName, lastName: lastName)
        let title = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
        let chat = makeChat(
            id: id,
            title: title,
            isPinned: isPinned,
            isMarkedAsUnread: isMarkedAsUnread,
            unreadCount: unreadCount,
        )
        return CustomChat(
            chat: chat,
            position: chat.positions[0],
            unreadCount: unreadCount,
            type: .user(user),
        )
    }

    static func makeUser(id: Int64, firstName: String, lastName: String) -> User {
        User(
            accentColorId: 0,
            activeStoryState: nil,
            addedToAttachmentMenu: false,
            backgroundCustomEmojiId: 0,
            emojiStatus: nil,
            firstName: firstName,
            haveAccess: true,
            id: id,
            isCloseFriend: false,
            isContact: true,
            isMutualContact: true,
            isPremium: false,
            isSupport: false,
            languageCode: "en",
            lastName: lastName,
            paidMessageStarCount: 0,
            phoneNumber: "",
            profileAccentColorId: 0,
            profileBackgroundCustomEmojiId: 0,
            profilePhoto: nil,
            restrictionInfo: nil,
            restrictsNewChats: false,
            status: .userStatusOffline(UserStatusOffline(wasOnline: 0)),
            type: .userTypeRegular,
            upgradedGiftColors: nil,
            usernames: nil,
            verificationStatus: nil,
        )
    }

    static func makeChat(
        id: Int64,
        title: String,
        isPinned: Bool,
        isMarkedAsUnread: Bool,
        unreadCount: Int,
    ) -> Chat {
        Chat(
            accentColorId: 0,
            actionBar: nil,
            availableReactions: .chatAvailableReactionsAll(ChatAvailableReactionsAll(maxReactionCount: 11)),
            background: nil,
            backgroundCustomEmojiId: 0,
            blockList: nil,
            businessBotManageBar: nil,
            canBeDeletedForAllUsers: false,
            canBeDeletedOnlyForSelf: true,
            canBeReported: false,
            chatLists: [.chatListMain],
            clientData: "",
            defaultDisableNotification: false,
            draftMessage: nil,
            emojiStatus: nil,
            hasProtectedContent: false,
            hasScheduledMessages: false,
            id: id,
            isMarkedAsUnread: isMarkedAsUnread,
            isTranslatable: false,
            lastMessage: nil,
            lastReadInboxMessageId: 0,
            lastReadOutboxMessageId: 0,
            messageAutoDeleteTime: 0,
            messageSenderId: nil,
            notificationSettings: ChatNotificationSettings(
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
            ),
            pendingJoinRequests: nil,
            permissions: ChatPermissions(
                canAddLinkPreviews: true,
                canChangeInfo: true,
                canCreateTopics: true,
                canEditTag: true,
                canInviteUsers: true,
                canPinMessages: true,
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
            ),
            photo: nil,
            positions: [ChatPosition(isPinned: isPinned, list: .chatListMain, order: TdInt64(id), source: nil)],
            profileAccentColorId: 0,
            profileBackgroundCustomEmojiId: 0,
            replyMarkupMessageId: 0,
            theme: nil,
            title: title,
            type: .chatTypePrivate(ChatTypePrivate(userId: id)),
            unreadCount: unreadCount,
            unreadMentionCount: 0,
            unreadPollVoteCount: 0,
            unreadReactionCount: 0,
            upgradedGiftColors: nil,
            videoChat: VideoChat(defaultParticipantId: nil, groupCallId: 0, hasParticipants: false),
            viewAsTopics: false,
        )
    }
}
#endif
