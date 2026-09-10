// ChatVM+Publishers.swift

import Combine
import SwiftUI
@preconcurrency import TDLibKit

extension ChatVM {
    func setPublishers() {
        nc.publisher(&cancellables, for: .localScrollToLastIfNeeded) { [weak self] _ in
            guard let self, isAtBottom else { return }
            Task.main { self.scrollToLast() }
        }
        service.messagePublisher(chatId: customChat.chat.id)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in
                Task { @MainActor in self?.handle(snapshot) }
            }
            .store(in: &cancellables)
        let chatType = customChat.type
        service.updatePublisher
            .filter { isConversationStatusUpdate($0, for: chatType) }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] update in
                Task { @MainActor in self?.updateConversationStatus(update) }
            }
            .store(in: &cancellables)
        service.updatePublisher
            .compactMap { update -> UpdateFavoriteStickers? in
                guard case .updateFavoriteStickers(let value) = update else { return nil }
                return value
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] update in
                Task { @MainActor in self?.favoriteStickers.apply(update) }
            }
            .store(in: &cancellables)
        let chatId = customChat.chat.id
        service.updatePublisher
            .compactMap { update -> Int? in
                guard case .updateChatOnlineMemberCount(let value) = update, value.chatId == chatId else { return nil }
                return value.onlineMemberCount
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] count in
                Task { @MainActor in self?.onlineMemberCount = count }
            }
            .store(in: &cancellables)
    }

    @MainActor private func updateConversationStatus(_ update: Update) {
        let status: String? =
            switch (customChat.type, update) {
            case (.group(let group), .updateBasicGroup(let value)) where group.id == value.basicGroup.id:
                conversationGroupStatus(memberCount: value.basicGroup.memberCount)
            case (.group(let group), .updateBasicGroupFullInfo(let value)) where group.id == value.basicGroupId:
                conversationGroupStatus(memberCount: value.basicGroupFullInfo.members.count)
            case (.supergroup(let group), .updateSupergroup(let value)) where group.id == value.supergroup.id:
                conversationSupergroupStatus(
                    isChannel: value.supergroup.isChannel,
                    memberCount: value.supergroup.memberCount,
                )
            case (.supergroup(let group), .updateSupergroupFullInfo(let value))
                where group.id == value.supergroupId:
                conversationSupergroupStatus(
                    isChannel: group.isChannel,
                    memberCount: value.supergroupFullInfo.memberCount,
                )
            default:
                nil
            }

        guard let status else { return }
        withAnimation { onlineStatus = status }
    }

    @MainActor private func handle(_ snapshot: TelegramMessageSnapshot) {
        if let appliedMessageSnapshotVersion, snapshot.version <= appliedMessageSnapshotVersion {
            return
        }
        appliedMessageSnapshotVersion = snapshot.version
        latestMessageSnapshot = snapshot
        if loadedMessageIds.isEmpty, initialMessageId == nil, snapshot.hasMergedHistory {
            let matchingIds = snapshot.orderedMessageIds
                .filter { snapshot.messages[$0].map(messageMatchesTopic) ?? false }
            loadedMessageIds.formUnion(matchingIds.suffix(30))
        }
        renderStore.completeRefreshesIfMerged(messages: snapshot.messages)

        guard let change = snapshot.change else {
            reconcileMessages(with: snapshot)
            return
        }

        switch change {
        case .readInbox(let value):
            customChat.unreadCount = value.unreadCount
            reconcileMessages(with: snapshot)
        case .readOutbox(let value):
            customChat.lastReadOutboxMessageId = value.lastReadOutboxMessageId
            reconcileMessages(with: snapshot)
        case .newMessage(let value):
            if messageMatchesTopic(value.message) {
                if !value.message.isOutgoing {
                    ServiceSoundManager.shared.playIncomingMessageIfAppropriate(isMuted: customChat.isMuted)
                }
                loadedMessageIds.insert(value.message.id)
                pendingScrollMessageIds.insert(value.message.id)
            }
            reconcileMessages(with: snapshot)
        case .deleteMessages:
            reconcileMessages(with: snapshot)
        case .messageContentChanged(let value):
            invalidateMessageAndReplies(messageId: value.messageId, version: snapshot.version)
            refreshMessage(messageId: value.messageId, version: snapshot.version)
        case .messageEdited(let value):
            invalidateMessageAndReplies(messageId: value.messageId, version: snapshot.version)
            refreshMessage(messageId: value.messageId, version: snapshot.version)
        case .messageInteractionInfo(let value):
            renderStore.invalidate(messageId: value.messageId, version: snapshot.version)
            refreshMessage(messageId: value.messageId, version: snapshot.version)
        case .messagePinChanged(let value):
            renderStore.invalidate(messageId: value.messageId, version: snapshot.version)
            refreshMessage(messageId: value.messageId, version: snapshot.version)
            refreshPinnedMessages()
        case .messageSendSucceeded(let value):
            guard messageMatchesTopic(value.message) else {
                reconcileMessages(with: snapshot)
                return
            }
            if value.message.isOutgoing {
                ServiceSoundManager.shared.playMessageDelivered()
            }
            loadedMessageIds.insert(value.message.id)
            // A successful send replaces TDLib's temporary message id with a permanent one.
            // Never mutate the id of the CustomMessage already mounted in SwiftUI's ForEach:
            // its id is the row identity, and changing it behind Observation's back leaves the
            // accessibility element attached to the temporary row. Render a new model instead.
            renderedMessages.removeValue(forKey: value.oldMessageId)
            renderStore.invalidate(messageId: value.message.id, version: snapshot.version)
            if pendingScrollMessageIds.remove(value.oldMessageId) != nil {
                pendingScrollMessageIds.insert(value.message.id)
            }
            reconcileMessages(with: snapshot)
        case .messageSendFailed(let value):
            guard messageMatchesTopic(value.message) else {
                reconcileMessages(with: snapshot)
                return
            }
            messageActionError = "Message couldn't be sent: \(telegramErrorDescription(value.error))"
            loadedMessageIds.insert(value.message.id)
            renderedMessages.removeValue(forKey: value.oldMessageId)
            renderStore.invalidate(messageId: value.message.id, version: snapshot.version)
            if pendingScrollMessageIds.remove(value.oldMessageId) != nil {
                pendingScrollMessageIds.insert(value.message.id)
            }
            reconcileMessages(with: snapshot)
        case .userStatus(let value):
            withAnimation { onlineStatus = getOnlineStatus(from: value.status) }
        case .chatAction(let value):
            guard messageTopic == nil || value.topicId == messageTopic else { return }
            updateChatAction(value)
        case .historyMerged:
            reconcileMessages(with: snapshot)
        }
    }

    @MainActor private func reconcileMessages(with snapshot: TelegramMessageSnapshot) {
        // The shared store retains a chat's entire history for the app's lifetime; only
        // reconcile/render the bounded window this ChatVM has actually paged in or received live,
        // otherwise reopening a chat scrolled deep into earlier would re-render its whole backlog.
        let currentIds = Set(snapshot.orderedMessageIds).intersection(loadedMessageIds)
        renderedMessages = renderedMessages.filter { currentIds.contains($0.key) }
        provisionalMessageIds.formIntersection(currentIds)
        let toRender = renderStore.reconcile(currentIds: currentIds, messages: snapshot.messages)

        for (message, invalidationVersion) in toRender {
            renderMessage(message, invalidationVersion: invalidationVersion)
        }

        rebuildDisplayedMessages(from: snapshot)
        updateInitialLoadingState(from: snapshot)
    }

    @MainActor private func renderMessage(_ message: Message, invalidationVersion: UInt64) {
        let generation = renderStore.beginRendering(message, invalidationVersion: invalidationVersion)

        if renderedMessages[message.id] == nil {
            renderedMessages[message.id] = initialCustomMessage(from: message)
            provisionalMessageIds.insert(message.id)
        }

        Task.background {
            await self.messageRenderLimiter.acquire()
            let customMessage = await self.getCustomMessage(from: message)
            await self.messageRenderLimiter.release()
            await main {
                guard self.renderStore.isRenderStillCurrent(
                    messageId: message.id,
                    generation: generation,
                    invalidationVersion: invalidationVersion,
                    currentMessage: self.latestMessageSnapshot?.messages[message.id],
                )
                else { return }

                self.renderStore.commitRender(
                    messageId: message.id,
                    message: message,
                    invalidationVersion: invalidationVersion,
                )
                self.renderedMessages[message.id] = customMessage
                let replacedProvisionalMessage = self.provisionalMessageIds.remove(message.id) != nil
                if self.replyMessage?.message.id == message.id {
                    self.replyMessage = customMessage
                }
                if self.isChatTranslationEnabled {
                    self.ensureMessageTranslated(customMessage)
                }
                if !replacedProvisionalMessage || self.provisionalMessageIds.isEmpty {
                    self.scheduleDisplayedMessagesRebuild()
                }
            }
        }
    }

    private func initialCustomMessage(from message: Message) -> CustomMessage {
        let customMessage = CustomMessage(message: message, properties: .default)
        if message.mediaAlbumId != 0, telegramMessageSupportsVisualAlbum(message) {
            customMessage.album.append(message)
        }
        customMessage.formattedText =
            switch message.content {
            case .messageText(let messageText):
                messageText.text
            case .messageAudio, .messageDocument, .messagePhoto, .messageVideo, .messageVoiceNote:
                telegramMessageFormattedText(message)
            case .messagePoll, .messageSticker, .messageVideoNote:
                nil
            default:
                FormattedText(entities: [], text: telegramMessageContentDescription(message))
            }
        return customMessage
    }

    @MainActor private func scheduleDisplayedMessagesRebuild() {
        guard displayedMessagesRebuildTask == nil else { return }
        displayedMessagesRebuildTask = Task { @MainActor [weak self] in
            // Render completions already arrive on the main actor. Yielding once coalesces all
            // completions queued by the current render pass without relying on a timing constant.
            await Task.yield()
            guard let self, !Task.isCancelled else { return }
            displayedMessagesRebuildTask = nil
            guard let snapshot = latestMessageSnapshot else { return }
            rebuildDisplayedMessages(from: snapshot)
            updateInitialLoadingState(from: snapshot)
        }
    }

    @MainActor private func rebuildDisplayedMessages(from snapshot: TelegramMessageSnapshot) {
        var displayedMessages = [CustomMessage]()
        // The shared store retains up to 500 messages per chat, while this ChatVM intentionally
        // displays only its paged window. Scanning the whole retained history here runs on the
        // main actor and made reopening heavily visited/media-rich chats noticeably stall.
        let orderedLoadedMessageIds = snapshot.orderedMessageIds.filter(loadedMessageIds.contains)
        let groups = telegramVisualMessageAlbumGroups(
            orderedMessageIds: orderedLoadedMessageIds,
            messages: snapshot.messages,
        )

        for group in groups {
            guard group.messageIds.allSatisfy({ renderedMessages[$0] != nil }),
                  let representative = renderedMessages[group.representativeMessageId]
            else { continue }

            if group.isAlbum {
                let album = group.messageIds.compactMap { snapshot.messages[$0] }
                if representative.album.map(\.id) != album.map(\.id) {
                    representative.album = album
                }
                if let caption = album.lazy
                    .compactMap(telegramMessageFormattedText)
                    .first(where: { !$0.text.isEmpty })
                {
                    representative.formattedText = caption
                }
            } else if !representative.album.isEmpty {
                representative.album = []
            }
            displayedMessages.append(representative)
        }

        let currentIds = messages.map(\.id)
        let displayedIds = displayedMessages.map(\.id)
        if currentIds != displayedIds {
            let currentIdSet = Set(currentIds)
            let displayedIdSet = Set(displayedIds)
            let addedIds = displayedIdSet.subtracting(currentIdSet)
            let removedCount = currentIdSet.subtracting(displayedIdSet).count
            let isSmallChange = addedIds.count + removedCount <= 2
            let additionsAreAtBottom = addedIds.isEmpty || addedIds.allSatisfy { $0 == displayedIds.last }
            if initialMessagesLoaded, isSmallChange, additionsAreAtBottom {
                withAnimation { messages = displayedMessages }
            } else {
                messages = displayedMessages
            }
        } else {
            for index in messages.indices where messages[index] !== displayedMessages[index] {
                if initialMessagesLoaded {
                    withAnimation { messages[index] = displayedMessages[index] }
                } else {
                    messages[index] = displayedMessages[index]
                }
            }
        }

        let updatedAudioPlaylist = displayedMessages.compactMap { $0.messageAudio?.audio }
        if audioPlaylist.map(\.audio.id) != updatedAudioPlaylist.map(\.audio.id) {
            audioPlaylist = updatedAudioPlaylist
        }

        let displayedMessageIds = Set(messages.flatMap { message in
            [message.id] + message.album.map(\.id)
        })
        let readyToScroll = pendingScrollMessageIds.intersection(displayedMessageIds)
        if !readyToScroll.isEmpty {
            pendingScrollMessageIds.subtract(readyToScroll)
            nc.post(name: .localScrollToLastIfNeeded)
        }

        if let targetMessageId = pendingNavigationMessageId,
           messages.contains(where: { $0.id == targetMessageId })
        {
            pendingNavigationMessageId = nil
            if pendingNavigationMovesAccessibilityFocus {
                accessibilityFocusRequestMessageId = targetMessageId
            } else {
                scrollRequestMessageId = targetMessageId
            }
            pendingNavigationMovesAccessibilityFocus = false
        }
    }

    @MainActor private func updateInitialLoadingState(from snapshot: TelegramMessageSnapshot) {
        guard !initialMessagesLoaded, snapshot.hasMergedHistory else { return }
        let relevantIds = Set(snapshot.orderedMessageIds).intersection(loadedMessageIds)
        let allMessagesRendered = relevantIds.allSatisfy { renderedMessages[$0] != nil }
        guard allMessagesRendered else { return }
        withAnimation { initialMessagesLoaded = true }
        refreshDetectedChatLanguage()
    }

    @MainActor private func invalidateMessageAndReplies(messageId: Int64, version: UInt64) {
        renderStore.invalidate(messageId: messageId, version: version)
        for (renderedId, renderedMessage) in renderedMessages
            where renderedMessage.replyToMessage?.id == messageId
        {
            renderStore.invalidate(messageId: renderedId, version: version)
        }
    }

    @MainActor private func refreshMessage(messageId: Int64, version: UInt64) {
        renderStore.beginRefresh(messageId: messageId, version: version)
        let chatId = customChat.chat.id
        Task.background {
            let refreshed = try? await self.service.getMessage(chatId: chatId, messageId: messageId)
            await main {
                guard self.renderStore.isRefreshStillCurrent(messageId: messageId, version: version) else { return }
                guard let refreshed else {
                    self.renderStore.cancelRefresh(messageId: messageId)
                    return
                }
                self.renderStore.stageRefreshedMessage(refreshed, for: messageId)
                self.service.mergeMessages(chatId: chatId, messages: [refreshed])
            }
        }
    }

    @MainActor private func updateChatAction(_ update: UpdateChatAction) {
        let status =
            switch update.action {
            case .chatActionTyping: "typing..."
            case .chatActionRecordingVideo: "recording video..."
            case .chatActionUploadingVideo: "uploading video..."
            case .chatActionRecordingVoiceNote: "recording voice note..."
            case .chatActionUploadingVoiceNote: "uploading voice note..."
            case .chatActionUploadingPhoto: "uploading photo..."
            case .chatActionUploadingDocument: "uploading voice document..."
            case .chatActionChoosingSticker: "choosing sticker..."
            case .chatActionChoosingLocation: "choosing location..."
            case .chatActionChoosingContact: "choosing contact..."
            case .chatActionStartPlayingGame: "playing game..."
            case .chatActionRecordingVideoNote: "recording video note..."
            case .chatActionUploadingVideoNote: "uploading video note..."
            case .chatActionWatchingAnimations(let watching): "watching animations...\(watching.emoji)"
            case .chatActionCancel: ""
            }
        withAnimation { actionStatus = status }
    }
}

private func isConversationStatusUpdate(_ update: Update, for chatType: CustomChat.CustomChatType) -> Bool {
    switch (chatType, update) {
    case (.group(let group), .updateBasicGroup(let value)):
        group.id == value.basicGroup.id
    case (.group(let group), .updateBasicGroupFullInfo(let value)):
        group.id == value.basicGroupId
    case (.supergroup(let group), .updateSupergroup(let value)):
        group.id == value.supergroup.id
    case (.supergroup(let group), .updateSupergroupFullInfo(let value)):
        group.id == value.supergroupId
    default:
        false
    }
}

// MARK: - MessageRenderLimiter

actor MessageRenderLimiter {
    // MARK: Lifecycle

    init(limit: Int) {
        self.availablePermits = max(1, limit)
    }

    // MARK: Internal

    func acquire() async {
        if availablePermits > 0 {
            availablePermits -= 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        if waiters.isEmpty {
            availablePermits += 1
        } else {
            waiters.removeFirst().resume()
        }
    }

    // MARK: Private

    private var availablePermits: Int
    private var waiters = [CheckedContinuation<Void, Never>]()
}
