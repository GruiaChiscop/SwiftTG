// MacSessionModel+History.swift

import TDLibKit

extension MacSessionModel {
    func loadLatestMessages() async {
        guard !isLoadingMessages,
              !isLoadingLatestMessages,
              let chatId = openedChatId
        else { return }

        historyRequestGeneration &+= 1
        let generation = historyRequestGeneration
        isLoadingOlderMessages = false
        isLoadingLatestMessages = true
        defer {
            if historyRequestGeneration == generation {
                isLoadingLatestMessages = false
            }
        }

        let (messagesById, reachedBeginning) = await fetchMessagesBackward(chatId: chatId, generation: generation)

        guard !Task.isCancelled,
              openedChatId == chatId,
              historyRequestGeneration == generation,
              let newestMessage = messagesById.values.max(by: { lhs, rhs in
                  if lhs.date == rhs.date {
                      return lhs.id < rhs.id
                  }
                  return lhs.date < rhs.date
              })
        else { return }

        canLoadOlderMessages = !reachedBeginning
        latestHistoryTargetMessageId = newestMessage.id
        let latestMessages = Array(messagesById.values)
        service.replaceMessageHistory(chatId: chatId, messages: latestMessages)
    }

    func loadOlderMessages() async -> Bool {
        guard canLoadOlderMessages,
              !isLoadingMessages,
              !isLoadingOlderMessages,
              let chatId = openedChatId,
              let anchorMessageId = messages.orderedMessageIds.first
        else { return false }

        let generation = historyRequestGeneration
        let knownMessageIds = Set(messages.orderedMessageIds)
        isLoadingOlderMessages = true
        defer {
            if historyRequestGeneration == generation {
                isLoadingOlderMessages = false
            }
        }

        guard let history = try? await service.getChatHistory(
            chatId: chatId,
            fromMessageId: anchorMessageId,
            limit: 21,
            offset: 0,
            onlyLocal: false,
        ), !Task.isCancelled,
        openedChatId == chatId,
        historyRequestGeneration == generation
        else { return false }

        let olderMessages = (history.messages ?? []).filter {
            $0.id != anchorMessageId && !knownMessageIds.contains($0.id)
        }
        guard !olderMessages.isEmpty else {
            canLoadOlderMessages = false
            return false
        }

        service.mergeMessageHistory(chatId: chatId, messages: olderMessages)
        return true
    }

    func loadInitialHistory(chatId: Int64, around targetMessageId: Int64? = nil) async -> [Message] {
        let generation = historyRequestGeneration

        if let targetMessageId {
            guard let history = try? await service.getChatHistory(
                chatId: chatId,
                fromMessageId: targetMessageId,
                limit: 51,
                offset: -25,
                onlyLocal: false,
            ), !Task.isCancelled,
            openedChatId == chatId,
            historyRequestGeneration == generation
            else { return [] }

            let foundMessages = history.messages ?? []
            service.mergeMessageHistory(chatId: chatId, messages: foundMessages)
            canLoadOlderMessages = !foundMessages.isEmpty
            return foundMessages
        }

        // A normal chat open is remote-capable from the first request. In particular, channels can
        // have only their latest post in TDLib's local cache; treating any nonempty local response
        // as a complete initial page leaves the conversation permanently stuck on that one post.
        // `fetchMessagesBackward` immediately continues from a one-message response until it fills
        // the initial page or TDLib reports that the beginning was reached, matching Unigram's
        // one-item fallback without publishing a succession of partial snapshots.
        let (messagesById, reachedBeginning) = await fetchMessagesBackward(
            chatId: chatId,
            generation: generation,
        )
        guard !Task.isCancelled, openedChatId == chatId, historyRequestGeneration == generation else {
            return Array(messagesById.values)
        }

        // Merge once the full initial batch is assembled rather than after each network page - a
        // cold chat (nothing synced locally yet) can need several sequential round trips here, and
        // publishing after every single one forces a full table reload each time, turning what
        // should be one clean reveal into a visibly janky, multi-second churn.
        if !messagesById.isEmpty {
            service.mergeMessageHistory(chatId: chatId, messages: Array(messagesById.values))
        }
        canLoadOlderMessages = !reachedBeginning && !messagesById.isEmpty
        return Array(messagesById.values)
    }

    // MARK: Private

    /// Pages backward from the newest known message, accumulating up to `targetCount` messages
    /// across at most `maxIterations` round trips. Shared by `loadLatestMessages` (bootstrap) and
    /// `loadInitialHistory` (jump-to-message with no target) - the only difference between the two
    /// call sites is what they do with the result once paging stops.
    ///
    /// `targetCount` matches iOS's initial page size deliberately, not just for parity: the
    /// resulting batch lands in `MacMessageTable`, where automatic row-height measurement still
    /// runs synchronously for each progressively inserted chunk. A cold chat with no local history
    /// assembles its whole first reveal from this batch, so keep it as small as still gives a
    /// reasonable first screenful.
    private func fetchMessagesBackward(
        chatId: Int64,
        generation: UInt64,
        targetCount: Int = 30,
        maxIterations: Int = 10,
        startingFromMessageId: Int64 = 0,
    ) async -> (messages: [Int64: Message], reachedBeginning: Bool) {
        var messagesById = [Int64: Message]()
        var fromMessageId = startingFromMessageId
        var reachedBeginning = false

        for _ in 0..<maxIterations {
            guard !Task.isCancelled,
                  openedChatId == chatId,
                  historyRequestGeneration == generation,
                  messagesById.count < targetCount
            else { break }

            let requestedCount = min(100, targetCount - messagesById.count + (fromMessageId == 0 ? 0 : 1))
            guard let history = try? await service.getChatHistory(
                chatId: chatId,
                fromMessageId: fromMessageId,
                limit: requestedCount,
                offset: 0,
                onlyLocal: false,
            ) else { break }
            let newMessages = (history.messages ?? []).filter { messagesById[$0.id] == nil }
            guard !newMessages.isEmpty else {
                reachedBeginning = true
                break
            }
            for message in newMessages {
                messagesById[message.id] = message
            }
            fromMessageId = messagesById.keys.min() ?? 0
        }

        return (messagesById, reachedBeginning)
    }
}
