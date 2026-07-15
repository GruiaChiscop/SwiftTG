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

        let targetCount = 50
        var messagesById = [Int64: Message]()
        var fromMessageId: Int64 = 0
        var reachedBeginning = false

        for _ in 0..<10 {
            guard !Task.isCancelled,
                  openedChatId == chatId,
                  historyRequestGeneration == generation,
                  messagesById.count < targetCount
            else { return }

            let requestedCount = min(100, targetCount - messagesById.count + (fromMessageId == 0 ? 0 : 1))
            guard let history = try? await service.getChatHistory(
                chatId: chatId,
                fromMessageId: fromMessageId,
                limit: requestedCount,
                offset: 0,
                onlyLocal: false,
            ) else { return }

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
        await preloadAccessibilityMetadata(for: latestMessages)
        guard !Task.isCancelled,
              openedChatId == chatId,
              historyRequestGeneration == generation
        else { return }
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

        await preloadAccessibilityMetadata(for: olderMessages)
        guard !Task.isCancelled,
              openedChatId == chatId,
              historyRequestGeneration == generation
        else { return false }
        service.mergeMessageHistory(chatId: chatId, messages: olderMessages)
        return true
    }

    func loadInitialHistory(chatId: Int64, around targetMessageId: Int64? = nil) async -> [Message] {
        let targetCount = 50
        let maxIterations = 10
        let generation = historyRequestGeneration
        var messagesById = [Int64: Message]()
        var fromMessageId: Int64 = targetMessageId ?? 0
        var reachedBeginning = false

        if targetMessageId != nil {
            guard let history = try? await service.getChatHistory(
                chatId: chatId,
                fromMessageId: fromMessageId,
                limit: 51,
                offset: -25,
                onlyLocal: false,
            ), !Task.isCancelled,
            openedChatId == chatId,
            historyRequestGeneration == generation
            else { return [] }

            let foundMessages = history.messages ?? []
            await preloadAccessibilityMetadata(for: foundMessages)
            guard !Task.isCancelled,
                  openedChatId == chatId,
                  historyRequestGeneration == generation
            else { return [] }
            service.mergeMessageHistory(chatId: chatId, messages: foundMessages)
            canLoadOlderMessages = !foundMessages.isEmpty
            return foundMessages
        }

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

            await preloadAccessibilityMetadata(for: newMessages)
            guard !Task.isCancelled,
                  openedChatId == chatId,
                  historyRequestGeneration == generation
            else { break }
            for message in newMessages {
                messagesById[message.id] = message
            }
            service.mergeMessageHistory(chatId: chatId, messages: newMessages)
            fromMessageId = messagesById.keys.min() ?? 0
        }

        if openedChatId == chatId, historyRequestGeneration == generation {
            canLoadOlderMessages = !reachedBeginning && !messagesById.isEmpty
        }
        return Array(messagesById.values)
    }

    private func preloadAccessibilityMetadata(for historyMessages: [Message]) async {
        var requests = [Task<Void, Never>]()
        for message in historyMessages {
            if !message.isOutgoing, messageSenderNames[message.id] == nil {
                requests.append(Task { [weak self] in
                    await self?.loadSenderName(for: message)
                })
            }
            if case .messageReplyToMessage = message.replyTo,
               messageReplyContexts[message.id] == nil
            {
                requests.append(Task { [weak self] in
                    await self?.loadReplyContext(for: message)
                })
            }
            if message.forwardInfo != nil, messageForwardedFrom[message.id] == nil {
                requests.append(Task { [weak self] in
                    await self?.loadForwardedFrom(for: message)
                })
            }
        }
        for request in requests {
            await request.value
        }
    }
}
