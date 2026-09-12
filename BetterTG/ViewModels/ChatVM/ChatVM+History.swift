// ChatVM+History.swift

@preconcurrency import TDLibKit

extension ChatVM {
    func loadInitialMessages() {
        guard conversationPreparationTask == nil else { return }

        let chatId = customChat.chat.id
        let service = service
        conversationPreparationTask = Task { @MainActor [weak self] in
            // With `forceRead: false`, TDLib only advances the read state for an open chat. Await
            // this before exposing loaded rows to the collection view so the first visible batch
            // cannot race the earlier fire-and-forget `openChat` call.
            _ = try? await service.openChat(chatId: chatId)
            guard let self, !Task.isCancelled else { return }

            if case .messageTopicForum(let forum) = messageTopic,
               let topic = try? await service.getForumTopic(
                   chatId: chatId,
                   forumTopicId: forum.forumTopicId,
               )
            {
                initialUnreadCount = topic.unreadCount
                initialLastReadInboxMessageId = topic.lastReadInboxMessageId
                conversationUnreadCount = topic.unreadCount
            } else if case .messageTopicThread(let thread) = messageTopic,
                      let info = try? await service.getMessageThread(
                          chatId: chatId,
                          messageId: thread.messageThreadId,
                      )
            {
                initialUnreadCount = info.unreadMessageCount
                conversationUnreadCount = info.unreadMessageCount
            }
            conversationPrepared = true
            conversationPreparationTask = nil
            if let latestMessageSnapshot {
                handle(latestMessageSnapshot)
            }
            loadMessages()
        }
    }

    func loadMessages() {
        guard loadingMessagesTask == nil, !hasReachedBeginningOfHistory else { return }
        let fromMessageId = messages.first?.message.id ?? initialMessageId ?? 0
        let loadsAroundInitialMessage = initialMessageId != nil && messages.isEmpty
        let initialWindowTarget =
            loadedMessageIds.isEmpty && initialMessageId == nil
                ? Self.initialHistoryWindowSize
                : nil
        loadingMessagesGeneration += 1
        let generation = loadingMessagesGeneration
        loadingMessagesTask = Task.background {
            await self._loadMessages(
                fromMessageId: fromMessageId,
                generation: generation,
                loadsAroundInitialMessage: loadsAroundInitialMessage,
                initialWindowTarget: initialWindowTarget,
            )
        }
    }

    func _loadMessages(
        fromMessageId: Int64,
        generation: Int,
        loadsAroundInitialMessage: Bool,
        initialWindowTarget: Int?,
    ) async {
        var collectedMessages = [Message]()
        var collectedIds = Set<Int64>()
        var nextFromMessageId = fromMessageId
        var reachedBeginning = false
        let maximumRequestCount = initialWindowTarget == nil ? 1 : 2

        for requestIndex in 0..<maximumRequestCount {
            let remainingInitialMessages = initialWindowTarget.map {
                max(1, $0 - collectedIds.count + (nextFromMessageId == 0 ? 0 : 1))
            }
            let limit = loadsAroundInitialMessage ? 31 : (remainingInitialMessages ?? 30)
            let offset = loadsAroundInitialMessage ? -15 : 0

            guard let history = try? await fetchHistoryPage(
                fromMessageId: nextFromMessageId,
                limit: limit,
                offset: offset,
            ), let page = history.messages else {
                break
            }

            if page.isEmpty {
                reachedBeginning = true
                break
            }

            for message in page where collectedIds.insert(message.id).inserted {
                collectedMessages.append(message)
            }

            guard let initialWindowTarget, collectedIds.count < initialWindowTarget,
                  requestIndex + 1 < maximumRequestCount,
                  let boundaryMessage = page.last(where: { $0.id != nextFromMessageId })
            else { break }
            nextFromMessageId = boundaryMessage.id
        }

        let loadedIds = collectedIds
        let didReachBeginning = reachedBeginning
        await main {
            self.loadedMessageIds.formUnion(loadedIds)
            if didReachBeginning {
                self.hasReachedBeginningOfHistory = true
            }
        }
        if !collectedMessages.isEmpty {
            service.mergeMessageHistory(chatId: customChat.chat.id, messages: collectedMessages)
        }
        await main {
            guard self.loadingMessagesGeneration == generation else { return }
            self.loadingMessagesTask = nil
        }
    }

    /// Dispatches to whichever TDLib history call matches `messageTopic` - `getChatHistory` for
    /// ordinary chats, `getMessageThreadHistory` for comment threads, `getForumTopicHistory` for
    /// forum topics. All three return `Messages`, so callers need no further branching.
    func fetchHistoryPage(fromMessageId: Int64, limit: Int, offset: Int) async throws -> Messages {
        switch messageTopic {
        case .messageTopicThread(let thread):
            try await service.getMessageThreadHistory(
                chatId: customChat.chat.id,
                fromMessageId: fromMessageId,
                limit: limit,
                messageId: thread.messageThreadId,
                offset: offset,
            )
        case .messageTopicForum(let forum):
            try await service.getForumTopicHistory(
                chatId: customChat.chat.id,
                forumTopicId: forum.forumTopicId,
                fromMessageId: fromMessageId,
                limit: limit,
                offset: offset,
            )
        case .messageTopicDirectMessages, .messageTopicSavedMessages, nil:
            try await service.getChatHistory(
                chatId: customChat.chat.id,
                fromMessageId: fromMessageId,
                limit: limit,
                offset: offset,
                onlyLocal: false,
            )
        }
    }

    /// TDLib excludes a comment thread's own starting message (the channel post's copy in the
    /// discussion group) from `getMessageThreadHistory` - `MessagesManager` only adds a message to
    /// the thread's local history if its thread id differs from its own id, so the root is always
    /// missing from that call and has to be fetched separately, matching Telegram-iOS/Unigram
    /// (both fetch it via a dedicated discussion-message lookup and splice it into the top of the
    /// scrollback themselves).
    func loadThreadRootMessageIfNeeded() {
        guard case .messageTopicThread(let thread) = messageTopic else { return }
        let chatId = customChat.chat.id
        Task.background {
            guard let rootMessage = try? await self.service.getMessage(
                chatId: chatId,
                messageId: thread.messageThreadId,
            ) else { return }
            self.service.mergeMessageHistory(chatId: chatId, messages: [rootMessage])
            await main {
                _ = self.loadedMessageIds.insert(rootMessage.id)
            }
        }
    }

    @MainActor func viewMessage(id: Int64) {
        pendingViewedMessageIds.insert(id)
        guard viewMessagesTask == nil else { return }

        viewMessagesTask = Task { @MainActor [weak self] in
            // One yield coalesces every row `willDisplay` reports within the current layout pass.
            await Task.yield()
            guard let self else { return }
            viewMessagesTask = nil

            let messageIds = Array(pendingViewedMessageIds)
            pendingViewedMessageIds.removeAll(keepingCapacity: true)
            guard !messageIds.isEmpty else { return }

            // Captured as plain values and sent from a detached task with no reference back to
            // `self`, so this read receipt still reaches TDLib even if the screen - and this
            // `ChatVM` - goes away the instant after: leaving a chat must never silently drop a
            // batch of messages that were already collected for "mark as read".
            let chatId = customChat.chat.id
            let service = service
            Task.background {
                try? await service.viewMessages(
                    chatId: chatId,
                    // The chat is open while this screen exists; don't force messages read after
                    // TDLib considers it closed during a navigation transition.
                    forceRead: false,
                    messageIds: messageIds,
                    source: .messageSourceChatHistory,
                )
            }

            // Best-effort unread-count refresh for the scroll-to-bottom badge - fine to skip if
            // the screen is already gone, unlike the read receipt above.
            if case .messageTopicForum(let forum) = messageTopic,
               let topic = try? await service.getForumTopic(chatId: chatId, forumTopicId: forum.forumTopicId)
            {
                conversationUnreadCount = topic.unreadCount
            } else if case .messageTopicThread(let thread) = messageTopic,
                      let info = try? await service.getMessageThread(chatId: chatId, messageId: thread.messageThreadId)
            {
                conversationUnreadCount = info.unreadMessageCount
            }
        }
    }
}
