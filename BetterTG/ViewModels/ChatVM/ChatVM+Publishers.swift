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
        let completedRefreshes = refreshedMessagesAwaitingMerge.compactMap { messageId, message in
            snapshot.messages[messageId] == message ? messageId : nil
        }
        for messageId in completedRefreshes {
            refreshedMessagesAwaitingMerge[messageId] = nil
            refreshVersions[messageId] = nil
        }

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
            pendingScrollMessageIds.insert(value.message.id)
            reconcileMessages(with: snapshot)
        case .deleteMessages:
            reconcileMessages(with: snapshot)
        case .messageEdited(let value):
            invalidateMessageAndReplies(messageId: value.messageId, version: snapshot.version)
            refreshMessage(messageId: value.messageId, version: snapshot.version)
        case .messagePinChanged(let value):
            messageInvalidationVersions[value.messageId] = snapshot.version
            refreshMessage(messageId: value.messageId, version: snapshot.version)
        case .messageSendSucceeded(let value):
            if value.message.isOutgoing {
                ServiceSoundManager.shared.playMessageDelivered()
            }
            if let rendered = renderedMessages.removeValue(forKey: value.oldMessageId) {
                rendered.message = value.message
                renderedMessages[value.message.id] = rendered
                renderedInvalidationVersions[value.message.id] =
                    renderedInvalidationVersions.removeValue(forKey: value.oldMessageId) ?? 0
                messageInvalidationVersions[value.message.id] = snapshot.version
            }
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
        let currentIds = Set(snapshot.orderedMessageIds)
        renderedMessages = renderedMessages.filter { currentIds.contains($0.key) }
        renderedInvalidationVersions = renderedInvalidationVersions.filter { currentIds.contains($0.key) }
        renderingMessages = renderingMessages.filter { currentIds.contains($0.key) }
        renderingInvalidationVersions = renderingInvalidationVersions.filter { currentIds.contains($0.key) }
        renderGenerations = renderGenerations.filter { currentIds.contains($0.key) }
        messageInvalidationVersions = messageInvalidationVersions.filter { currentIds.contains($0.key) }

        rebuildDisplayedMessages(from: snapshot)

        for messageId in snapshot.orderedMessageIds {
            guard let message = snapshot.messages[messageId] else { continue }
            let invalidationVersion = messageInvalidationVersions[messageId] ?? 0
            let renderedInvalidationVersion = renderedInvalidationVersions[messageId] ?? 0
            let needsRendering = renderedMessages[messageId]?.message != message
                || renderedInvalidationVersion < invalidationVersion
            guard needsRendering else { continue }
            guard refreshVersions[messageId] == nil else { continue }
            if renderingMessages[messageId] == message,
               renderingInvalidationVersions[messageId] == invalidationVersion
            {
                continue
            }
            renderMessage(message, invalidationVersion: invalidationVersion)
        }

        updateInitialLoadingState(from: snapshot)
    }

    @MainActor private func renderMessage(_ message: Message, invalidationVersion: UInt64) {
        nextRenderGeneration += 1
        let generation = nextRenderGeneration
        renderGenerations[message.id] = generation
        renderingMessages[message.id] = message
        renderingInvalidationVersions[message.id] = invalidationVersion

        Task.background {
            let customMessage = await self.getCustomMessage(from: message)
            await main {
                guard self.renderGenerations[message.id] == generation,
                      self.renderingInvalidationVersions[message.id] == invalidationVersion,
                      self.latestMessageSnapshot?.messages[message.id] == message,
                      (self.messageInvalidationVersions[message.id] ?? 0) == invalidationVersion
                else { return }

                self.renderingMessages[message.id] = nil
                self.renderingInvalidationVersions[message.id] = nil
                self.renderedMessages[message.id] = customMessage
                self.renderedInvalidationVersions[message.id] = invalidationVersion
                if self.replyMessage?.message.id == message.id {
                    self.replyMessage = customMessage
                }
                guard let snapshot = self.latestMessageSnapshot else { return }
                self.rebuildDisplayedMessages(from: snapshot)
                self.updateInitialLoadingState(from: snapshot)
            }
        }
    }

    @MainActor private func rebuildDisplayedMessages(from snapshot: TelegramMessageSnapshot) {
        var displayedMessages = [CustomMessage]()
        var processedAlbums = Set<TdInt64>()

        for messageId in snapshot.orderedMessageIds {
            guard let rawMessage = snapshot.messages[messageId] else { continue }
            if rawMessage.mediaAlbumId == 0 {
                if let rendered = renderedMessages[messageId] {
                    rendered.album = []
                    displayedMessages.append(rendered)
                }
                continue
            }

            let albumId = rawMessage.mediaAlbumId
            guard processedAlbums.insert(albumId).inserted else { continue }
            let albumMessageIds = snapshot.orderedMessageIds.filter {
                snapshot.messages[$0]?.mediaAlbumId == albumId
            }
            guard albumMessageIds.allSatisfy({ renderedMessages[$0] != nil }),
                  let representativeId = albumMessageIds.first,
                  let representative = renderedMessages[representativeId]
            else { continue }
            representative.album = albumMessageIds.compactMap { snapshot.messages[$0] }
            displayedMessages.append(representative)
        }

        let currentIds = messages.map(\.id)
        let displayedIds = displayedMessages.map(\.id)
        if currentIds != displayedIds {
            if initialMessagesLoaded {
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

        let readyToScroll = pendingScrollMessageIds.filter { messageId in
            messages.contains { $0.id == messageId || $0.album.contains(where: { $0.id == messageId }) }
        }
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
        let allMessagesRendered = snapshot.orderedMessageIds.allSatisfy { renderedMessages[$0] != nil }
        guard allMessagesRendered else { return }
        withAnimation { initialMessagesLoaded = true }
    }

    @MainActor private func invalidateMessageAndReplies(messageId: Int64, version: UInt64) {
        messageInvalidationVersions[messageId] = version
        for (renderedId, renderedMessage) in renderedMessages
            where renderedMessage.replyToMessage?.id == messageId
        {
            messageInvalidationVersions[renderedId] = version
        }
    }

    @MainActor private func refreshMessage(messageId: Int64, version: UInt64) {
        refreshVersions[messageId] = version
        refreshedMessagesAwaitingMerge[messageId] = nil
        let chatId = customChat.chat.id
        Task.background {
            let refreshed = try? await self.service.getMessage(chatId: chatId, messageId: messageId)
            await main {
                guard self.refreshVersions[messageId] == version else { return }
                guard let refreshed else {
                    self.refreshVersions[messageId] = nil
                    self.messageInvalidationVersions[messageId] = nil
                    return
                }
                self.refreshedMessagesAwaitingMerge[messageId] = refreshed
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
