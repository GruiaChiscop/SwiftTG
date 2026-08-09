// MacSessionModel+ChatActivation.swift

import AppKit
import Foundation
import TDLibKit

extension MacSessionModel {
    var chatItems: [ChatListItemState] {
        chatList.chatIds(in: selectedChatList).compactMap { chatList.items[$0] }
    }

    /// All chats across the main list and archive, regardless of which sidebar folder is currently
    /// selected - used by the forward picker, which shouldn't be scoped to `selectedChatList`.
    var allChatItems: [ChatListItemState] {
        let ids = chatList.chatIds(in: .chatListMain) + chatList.chatIds(in: .chatListArchive)
        return ids.compactMap { chatList.items[$0] }
    }

    var openedChat: ChatListItemState? {
        guard let openedChatId else { return nil }
        return chatList.items[openedChatId]
    }

    func activateFocusedChat() {
        guard let focusedChatId else { return }
        activateChat(focusedChatId)
    }

    /// `topic` scopes the opened chat to a single forum topic or comment thread (mirrors iOS's
    /// `ChatVM.messageTopic`) - `nil` is an ordinary full-chat open. Switching `topic` alone, with
    /// `chatId` unchanged (e.g. moving between two topics of the same forum group), goes through
    /// the same full reset/resubscribe path as switching chats entirely, since the message list,
    /// composer, and history-loading state all need to start over either way.
    func activateChat(_ chatId: Int64, messageId: Int64? = nil, topic: MessageTopic? = nil, topicTitle: String? = nil) {
        if openedChatId != chatId, isConversationSearchActive {
            endConversationSearch()
        }

        focusedChatId = chatId
        latestHistoryTargetMessageId = nil
        navigationTargetMessageId = messageId
        if openedChatId == chatId, openedTopic == topic {
            guard let messageId, messages.messages[messageId] == nil else { return }
            historyRequestGeneration &+= 1
            let generation = historyRequestGeneration
            openTask?.cancel()
            openTask = Task { [weak self] in
                guard let self else { return }
                let found = await loadInitialHistory(chatId: chatId, around: messageId)
                guard !Task.isCancelled, generation == historyRequestGeneration else { return }
                isLoadingMessages = false
                if !found.contains(where: { $0.id == messageId }) {
                    navigationTargetMessageId = nil
                }
            }
            return
        }

        saveCurrentDraft()
        let openingChat = chatList.items[chatId]
        openedUnreadCount = openingChat?.unreadCount ?? 0
        openedLastReadInboxMessageId = openingChat?.lastReadInboxMessageId ?? 0

        cancelVoiceRecording()
        selectedPhotoURLs = []
        selectedDocumentURLs = []

        let previousChatId = openedChatId
        openedChatId = chatId
        openedTopic = topic
        openedTopicTitle = topicTitle
        pinnedMessages = []
        pinnedMessagesError = nil
        refreshPinnedMessages(for: chatId)
        restoreDraft(openingChat?.draftMessage, chatId: chatId)
        prepareConversationHeader(for: chatId, fallbackKind: openingChat?.kind)
        messages = .empty(chatId: chatId)
        editingMessage = nil
        replyingToMessage = nil
        editMessageText = NSAttributedString(string: "")
        messageCapabilities = [:]
        messageAvailableReactions = [:]
        messageReplyContexts = [:]
        messageForwardedFrom = [:]
        messageSenderNames = [:]
        messageServiceDescriptions = [:]
        messageTranslations = [:]
        translationShownMessageIds = []
        translatingMessageIds = []
        messageTranslationEligibility = [:]
        loadedMessageIds = []
        detectedChatLanguage = nil
        isChatTranslationEnabled = TelegramChatTranslationPreferences.isEnabled(chatId: chatId)
        isLoadingMessages = true
        isLoadingOlderMessages = false
        isLoadingLatestMessages = false
        canLoadOlderMessages = true
        historyRequestGeneration &+= 1
        messageSubscription?.cancel()
        messageSubscription = service.messagePublisher(chatId: chatId)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in
                guard self?.openedChatId == snapshot.chatId else { return }
                self?.handleMessageSnapshot(snapshot)
            }

        openTask?.cancel()
        openTask = Task { [weak self] in
            guard let self else { return }
            if let previousChatId {
                // Closing the old chat is independent from opening the new one. Waiting for its
                // TDLib round trip delayed the new chat's local-history request for no UI benefit.
                Task { _ = try? await self.service.closeChat(chatId: previousChatId) }
            }
            guard !Task.isCancelled, openedChatId == chatId else { return }
            _ = try? await service.openChat(chatId: chatId)
            let historyMessages: [Message] =
                if messageId == nil,
                messages.hasMergedHistory,
                !messages.orderedMessageIds.isEmpty {
                    // The subscription already delivered this chat's retained history. Fetching and
                    // merging the same page again only increments the snapshot version and forces a
                    // second table refresh immediately after the cached rows became visible.
                    messages.orderedMessageIds.compactMap { self.messages.messages[$0] }
                } else {
                    await loadInitialHistory(chatId: chatId, around: messageId)
                }
            guard !Task.isCancelled, openedChatId == chatId else { return }
            if let newestMessageId = historyMessages.max(by: { $0.id < $1.id })?.id {
                _ = try? await service.viewMessages(
                    chatId: chatId,
                    forceRead: true,
                    messageIds: [newestMessageId],
                    source: .messageSourceChatHistory,
                )
            }
            isLoadingMessages = false
            refreshDetectedChatLanguage()
        }
    }

    func activateResolvedChat(_ chat: Chat, messageId: Int64?) async {
        service.mergeChatListChats([chat])
        if chatList.items[chat.id] == nil {
            let membership = await service.resolveMembership(for: chat)
            chatList.items[chat.id] = ChatListItemState(chat, membership: membership)
        }
        activateChat(chat.id, messageId: messageId)
    }

    /// Opens a channel post's comment thread, which lives in the channel's linked discussion
    /// group - a genuinely different chat, possibly one `chatList` doesn't know about yet if the
    /// user has never opened it directly (mirrors `activateResolvedChat`'s on-demand registration).
    /// Matches iOS's `TelegramCommentsChatView`: the thread is resolved before this is called, so
    /// there's no empty screen that fills in afterward.
    func openCommentThread(discussionChatId: Int64, messageThreadId: Int64, title: String) async {
        if chatList.items[discussionChatId] == nil {
            guard let chat = try? await service.getChat(chatId: discussionChatId) else {
                messageActionError = "Couldn't load this discussion."
                return
            }
            service.mergeChatListChats([chat])
            let membership = await service.resolveMembership(for: chat)
            chatList.items[discussionChatId] = ChatListItemState(chat, membership: membership)
        }
        if commentThreadReturnChatId == nil {
            commentThreadReturnChatId = openedChatId
        }
        activateChat(
            discussionChatId,
            topic: .messageTopicThread(MessageTopicThread(messageThreadId: messageThreadId)),
            topicTitle: title,
        )
    }

    /// Leaves the currently open forum topic or comment thread - back to the same chat's topic
    /// list for a forum topic, or back to the channel a comment thread was opened from.
    func closeOpenedTopic() {
        guard let openedChatId else { return }
        if let returnChatId = commentThreadReturnChatId {
            commentThreadReturnChatId = nil
            activateChat(returnChatId, topic: nil)
        } else {
            activateChat(openedChatId, topic: nil)
        }
    }

    func navigateToRepliedMessage(from message: Message) {
        guard let context = messageReplyContexts[message.id], let messageId = context.messageId else { return }
        if context.chatId == openedChatId {
            activateChat(context.chatId, messageId: messageId)
            return
        }
        Task { [weak self] in
            guard let self else { return }
            guard let chat = try? await service.getChat(chatId: context.chatId) else {
                messageActionError = "This chat is private or unavailable."
                return
            }
            await activateResolvedChat(chat, messageId: messageId)
        }
    }

    func navigateToContact(userId: Int64) {
        Task { [weak self] in
            guard let self else { return }
            guard let chat = try? await service.createPrivateChat(force: false, userId: userId) else {
                messageActionError = "This contact can't be opened."
                return
            }
            await activateResolvedChat(chat, messageId: nil)
        }
    }

    func addContact(_ presentation: TelegramContactPresentation) {
        guard !isAddingContact else { return }
        isAddingContact = true
        messageActionError = nil
        Task { [weak self] in
            guard let self else { return }
            defer { isAddingContact = false }
            do {
                let imported = ImportedContact(
                    firstName: presentation.firstName,
                    lastName: presentation.lastName,
                    note: nil,
                    phoneNumber: presentation.phoneNumber,
                )
                let result = try await service.importContacts(contacts: [imported])
                guard result.userIds.first.map({ $0 != 0 }) == true else {
                    messageActionError = "No Telegram account was found for this phone number."
                    return
                }
                if let window = NSApp.keyWindow ?? NSApp.mainWindow {
                    NSAccessibility.post(
                        element: window,
                        notification: .announcementRequested,
                        userInfo: [
                            .announcement: "Added to Contacts",
                            .priority: NSAccessibilityPriorityLevel.high.rawValue,
                        ],
                    )
                }
            } catch {
                guard !Task.isCancelled else { return }
                messageActionError = "Contact couldn't be added: \(telegramErrorDescription(error))"
            }
        }
    }

    func navigateToForwardOrigin(from message: Message) {
        guard let origin = message.forwardInfo?.origin else { return }
        Task { [weak self] in
            guard let self else { return }
            let destination: (chat: Chat, messageId: Int64?)?
            switch origin {
            case .messageOriginUser(let user):
                if let chat = try? await service.createPrivateChat(force: false, userId: user.senderUserId) {
                    destination = (chat, nil)
                } else {
                    destination = nil
                }
            case .messageOriginChat(let chat):
                if let resolvedChat = try? await service.getChat(chatId: chat.senderChatId) {
                    destination = (resolvedChat, nil)
                } else {
                    destination = nil
                }
            case .messageOriginChannel(let channel):
                if let chat = try? await service.getChat(chatId: channel.chatId) {
                    destination = (chat, channel.messageId == 0 ? nil : channel.messageId)
                } else {
                    destination = nil
                }
            case .messageOriginHiddenUser:
                return
            }
            guard let destination else {
                messageActionError = "This user or chat is private or unavailable."
                return
            }
            await activateResolvedChat(destination.chat, messageId: destination.messageId)
        }
    }

    // MARK: Private

    /// True when `openedTopic` is unset (ordinary full-chat mode) or `message` belongs to it -
    /// mirrors iOS's `ChatVM.messageMatchesTopic(_:)`.
    private func messageMatchesOpenedTopic(_ message: Message) -> Bool {
        guard let openedTopic else { return true }
        return message.topicId == openedTopic
    }

    /// Restricts a snapshot to `openedTopic`'s messages - the shared store publishes every message
    /// in the chat regardless of thread/topic, so a comment thread or forum topic needs this
    /// filter applied before anything (row list, unread count) reads from it.
    private func presentationSnapshot(from snapshot: TelegramMessageSnapshot) -> TelegramMessageSnapshot {
        let topicMessageIds =
            if openedTopic == nil {
                snapshot.orderedMessageIds
            } else {
                snapshot.orderedMessageIds.filter {
                    snapshot.messages[$0].map(messageMatchesOpenedTopic) ?? false
                }
            }

        // A CurrentValueSubject immediately replays the store's retained snapshot to a new chat
        // subscription. Seed only a first screenful from that replay; older ids become visible
        // explicitly through `loadOlderMessages()` instead of all being mounted in one List diff.
        if loadedMessageIds.isEmpty {
            loadedMessageIds.formUnion(topicMessageIds.suffix(Self.initialHistoryWindowSize))
        }

        let filteredIds = topicMessageIds.filter(loadedMessageIds.contains)
        let filteredMessages = Dictionary(uniqueKeysWithValues: filteredIds.compactMap { messageId in
            snapshot.messages[messageId].map { (messageId, $0) }
        })
        return TelegramMessageSnapshot(
            chatId: snapshot.chatId,
            version: snapshot.version,
            messages: filteredMessages,
            orderedMessageIds: filteredIds,
            unreadCount: snapshot.unreadCount,
            hasMergedHistory: snapshot.hasMergedHistory,
            change: snapshot.change,
        )
    }

    private func handleMessageSnapshot(_ snapshot: TelegramMessageSnapshot) {
        switch snapshot.change {
        case .chatAction, .readInbox, .readOutbox, .userStatus:
            // None of these touch `messages`/`orderedMessageIds` (see `TelegramMessageStore.reduce`),
            // and nothing on macOS reads `messages.unreadCount` or `messages.change` for them - only
            // `MacMessageTable`'s `.onChange(of: model.messages.version)` does, which otherwise forces
            // a full message-list re-diff on every typing indicator, read receipt, or online-status
            // ping for the open chat. That diff is expensive enough (SwiftUI's List/OutlineListCoordinator
            // reconciliation) that a burst of these arriving right as a chat opens visibly froze the UI.
            return
        default:
            break
        }

        // Keep live row identity in the presented window while still excluding retained history
        // that this conversation instance has not paged into.
        switch snapshot.change {
        case .newMessage(let update) where messageMatchesOpenedTopic(update.message):
            loadedMessageIds.insert(update.message.id)
        case .messageSendSucceeded(let update) where messageMatchesOpenedTopic(update.message):
            loadedMessageIds.remove(update.oldMessageId)
            loadedMessageIds.insert(update.message.id)
        case .messageSendFailed(let update) where messageMatchesOpenedTopic(update.message):
            loadedMessageIds.remove(update.oldMessageId)
            loadedMessageIds.insert(update.message.id)
        case .deleteMessages(let update):
            loadedMessageIds.subtract(update.messageIds)
        default:
            break
        }

        messages = presentationSnapshot(from: snapshot)
        switch snapshot.change {
        case .newMessage(let update) where !update.message.isOutgoing && messageMatchesOpenedTopic(update.message):
            let isMuted = (chatList.items[snapshot.chatId]?.notificationSettings?.muteFor ?? 0) > 0
            MacServiceSoundManager.shared.playIncomingMessageIfAppropriate(isMuted: isMuted)
            if isChatTranslationEnabled {
                ensureTranslation(for: update.message)
            }
        case .messageSendSucceeded(let update)
            where update.message.isOutgoing && messageMatchesOpenedTopic(update.message):
            MacServiceSoundManager.shared.playMessageDelivered()
        case .messageSendFailed(let update) where messageMatchesOpenedTopic(update.message):
            messageActionError = "Message couldn't be sent: \(telegramErrorDescription(update.error))"
        default:
            break
        }

        // The four cases below all now carry enough state in their own update payload for
        // `TelegramMessageStore.reduce(_:)` to patch its cached `Message` directly (see
        // `Message.applying`), so `messages` above already reflects the change - no need to
        // round-trip a `getMessage` RPC here just to pick it up. Only the message's cached
        // capabilities (edit/pin/reaction permissions) still need invalidating, since those
        // aren't part of `Message` itself.
        if case .messagePinChanged = snapshot.change {
            refreshPinnedMessages()
        }
        let messageId: Int64? =
            switch snapshot.change {
            case .messageContentChanged(let update):
                update.messageId
            case .messageEdited(let update):
                update.messageId
            case .messageInteractionInfo(let update):
                update.messageId
            case .messagePinChanged(let update):
                update.messageId
            default:
                nil
            }
        guard let messageId else { return }
        messageCapabilities[messageId] = nil
    }
}
