// ChatVM+Publishers.swift

import Combine
import SwiftUI
import TDLibKit

extension ChatVM {
    func setPublishers() {
        nc.publisher(&cancellables, for: .localScrollToLastOnFocus) { [weak self] _ in
            guard let self, scrollOnFocus else { return }
            Task.main { self.scrollToLast() }
        }
        service.messagePublisher(chatId: customChat.chat.id)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in
                Task { @MainActor in self?.handle(snapshot) }
            }
            .store(in: &cancellables)
    }

    @MainActor private func handle(_ snapshot: TelegramMessageSnapshot) {
        if let appliedMessageSnapshotVersion, snapshot.version <= appliedMessageSnapshotVersion {
            return
        }
        appliedMessageSnapshotVersion = snapshot.version
        latestMessageSnapshot = snapshot
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
            if !value.message.isOutgoing {
                ServiceSoundManager.shared.playIncomingMessageIfAppropriate(isMuted: customChat.isMuted)
            }
            loadedMessageIds.insert(value.message.id)
            pendingScrollMessageIds.insert(value.message.id)
            reconcileMessages(with: snapshot)
        case .deleteMessages:
            reconcileMessages(with: snapshot)
        case .messageEdited(let value):
            invalidateMessageAndReplies(messageId: value.messageId, version: snapshot.version)
            refreshMessage(messageId: value.messageId, version: snapshot.version)
        case .messageInteractionInfo(let value):
            renderStore.invalidate(messageId: value.messageId, version: snapshot.version)
            refreshMessage(messageId: value.messageId, version: snapshot.version)
        case .messagePinChanged(let value):
            renderStore.invalidate(messageId: value.messageId, version: snapshot.version)
            refreshMessage(messageId: value.messageId, version: snapshot.version)
        case .messageSendSucceeded(let value):
            if value.message.isOutgoing {
                ServiceSoundManager.shared.playMessageDelivered()
            }
            loadedMessageIds.insert(value.message.id)
            if let rendered = renderedMessages.removeValue(forKey: value.oldMessageId) {
                rendered.message = value.message
                renderedMessages[value.message.id] = rendered
            }
            renderStore.migrateRenderedResult(
                from: value.oldMessageId,
                to: value.message,
                invalidationVersion: snapshot.version,
            )
            if pendingScrollMessageIds.remove(value.oldMessageId) != nil {
                pendingScrollMessageIds.insert(value.message.id)
            }
            reconcileMessages(with: snapshot)
        case .userStatus(let value):
            withAnimation { onlineStatus = getOnlineStatus(from: value.status) }
        case .chatAction(let value):
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
        let toRender = renderStore.reconcile(currentIds: currentIds, messages: snapshot.messages)

        rebuildDisplayedMessages(from: snapshot)

        for (message, invalidationVersion) in toRender {
            renderMessage(message, invalidationVersion: invalidationVersion)
        }

        updateInitialLoadingState(from: snapshot)
    }

    @MainActor private func renderMessage(_ message: Message, invalidationVersion: UInt64) {
        let generation = renderStore.beginRendering(message, invalidationVersion: invalidationVersion)

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

                self.renderStore.commitRender(messageId: message.id, message: message, invalidationVersion: invalidationVersion)
                self.renderedMessages[message.id] = customMessage
                if self.replyMessage?.message.id == message.id {
                    self.replyMessage = customMessage
                }
                self.scheduleDisplayedMessagesRebuild()
            }
        }
    }

    @MainActor private func scheduleDisplayedMessagesRebuild() {
        guard displayedMessagesRebuildTask == nil else { return }
        displayedMessagesRebuildTask = Task { @MainActor [weak self] in
            try? await Task<Never, Never>.sleep(for: .milliseconds(40))
            guard let self, !Task.isCancelled else { return }
            displayedMessagesRebuildTask = nil
            guard let snapshot = latestMessageSnapshot else { return }
            rebuildDisplayedMessages(from: snapshot)
            updateInitialLoadingState(from: snapshot)
        }
    }

    @MainActor private func rebuildDisplayedMessages(from snapshot: TelegramMessageSnapshot) {
        var displayedMessages = [CustomMessage]()
        var processedAlbums = Set<TdInt64>()
        var albumMessageIds = [TdInt64: [Int64]]()

        for messageId in snapshot.orderedMessageIds {
            guard let albumId = snapshot.messages[messageId]?.mediaAlbumId, albumId != 0 else { continue }
            albumMessageIds[albumId, default: []].append(messageId)
        }

        for messageId in snapshot.orderedMessageIds {
            guard let rawMessage = snapshot.messages[messageId] else { continue }
            if rawMessage.mediaAlbumId == 0 {
                if let rendered = renderedMessages[messageId] {
                    if !rendered.album.isEmpty {
                        rendered.album = []
                    }
                    displayedMessages.append(rendered)
                }
                continue
            }

            let albumId = rawMessage.mediaAlbumId
            guard processedAlbums.insert(albumId).inserted else { continue }
            guard let messageIds = albumMessageIds[albumId],
                  messageIds.allSatisfy({ renderedMessages[$0] != nil }),
                  let representativeId = messageIds.first,
                  let representative = renderedMessages[representativeId]
            else { continue }
            let album = messageIds.compactMap { snapshot.messages[$0] }
            if representative.album.map(\.id) != album.map(\.id) {
                representative.album = album
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
            nc.post(name: .localScrollToLastOnFocus)
        }

        if let targetMessageId = pendingNavigationMessageId,
           messages.contains(where: { $0.id == targetMessageId })
        {
            pendingNavigationMessageId = nil
            accessibilityFocusRequestMessageId = targetMessageId
        }
    }

    @MainActor private func updateInitialLoadingState(from snapshot: TelegramMessageSnapshot) {
        guard !initialMessagesLoaded, snapshot.hasMergedHistory else { return }
        let relevantIds = Set(snapshot.orderedMessageIds).intersection(loadedMessageIds)
        let allMessagesRendered = relevantIds.allSatisfy { renderedMessages[$0] != nil }
        guard allMessagesRendered else { return }
        withAnimation { initialMessagesLoaded = true }
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
        guard case .messageSenderUser(let sender) = update.senderId,
              sender.userId == customChat.chat.id
        else { return }
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

actor MessageRenderLimiter {
    private var availablePermits: Int
    private var waiters = [CheckedContinuation<Void, Never>]()

    init(limit: Int) {
        availablePermits = max(1, limit)
    }

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
}
