// MacSessionModel+ConversationSearch.swift

import Foundation
import TDLibKit

extension MacSessionModel {
    var conversationSearchStatus: String {
        let query = conversationSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            return "Enter a search term"
        }
        if isSearchingConversation, conversationSearchResultIds.isEmpty {
            return "Searching"
        }
        if let conversationSearchError {
            return conversationSearchError
        }
        guard let index = conversationSearchSelectedIndex else {
            return "No results"
        }
        let total = max(conversationSearchTotalCount, conversationSearchResultIds.count)
        return "\(index + 1) of \(total)"
    }

    var canSelectOlderConversationSearchResult: Bool {
        guard let index = conversationSearchSelectedIndex else { return false }
        return index + 1 < conversationSearchResultIds.count
            || conversationSearchNextFromMessageId != 0
            || !conversationSearchNextOffset.isEmpty
    }

    var canSelectNewerConversationSearchResult: Bool {
        guard let index = conversationSearchSelectedIndex else { return false }
        return index > 0
    }

    func beginConversationSearch() {
        isConversationSearchActive = true
    }

    func endConversationSearch() {
        conversationSearchTask?.cancel()
        conversationSearchGeneration &+= 1
        isConversationSearchActive = false
        isSearchingConversation = false
        conversationSearchQuery = ""
        clearConversationSearchResults()
    }

    func conversationSearchQueryDidChange() {
        conversationSearchTask?.cancel()
        conversationSearchGeneration &+= 1
        let generation = conversationSearchGeneration
        let query = conversationSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        clearConversationSearchResults()

        guard !query.isEmpty else {
            isSearchingConversation = false
            return
        }

        isSearchingConversation = true
        conversationSearchTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(250))
                guard let self, !Task.isCancelled, generation == conversationSearchGeneration else { return }
                try await loadConversationSearchPage(query: query, generation: generation, selectsFirstNewResult: true)
            } catch is CancellationError {
                return
            } catch {
                guard let self, generation == conversationSearchGeneration else { return }
                isSearchingConversation = false
                conversationSearchError = error.localizedDescription
            }
        }
    }

    func selectOlderConversationSearchResult() {
        guard let index = conversationSearchSelectedIndex else { return }
        let nextIndex = index + 1
        if nextIndex < conversationSearchResultIds.count {
            selectConversationSearchResult(at: nextIndex)
            return
        }
        guard conversationSearchNextFromMessageId != 0 || !conversationSearchNextOffset.isEmpty else { return }

        let generation = conversationSearchGeneration
        let query = conversationSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        conversationSearchTask?.cancel()
        isSearchingConversation = true
        conversationSearchTask = Task { [weak self] in
            do {
                guard let self else { return }
                try await loadConversationSearchPage(
                    query: query,
                    generation: generation,
                    selectsFirstNewResult: true,
                )
            } catch is CancellationError {
                return
            } catch {
                guard let self, generation == conversationSearchGeneration else { return }
                isSearchingConversation = false
                conversationSearchError = error.localizedDescription
            }
        }
    }

    func selectNewerConversationSearchResult() {
        guard let index = conversationSearchSelectedIndex, index > 0 else { return }
        selectConversationSearchResult(at: index - 1)
    }

    private func loadConversationSearchPage(
        query: String,
        generation: UInt64,
        selectsFirstNewResult: Bool,
    ) async throws {
        guard let chatId = openedChatId else { return }
        let previousCount = conversationSearchResultIds.count
        let messages: [Message]
        let totalCount: Int

        if conversationSearchUsesSecretMessages || isOpenedSecretChat {
            let result = try await service.searchSecretMessages(
                chatId: chatId,
                filter: nil,
                limit: 50,
                offset: conversationSearchNextOffset,
                query: query,
            )
            messages = result.messages
            totalCount = result.totalCount
            conversationSearchNextOffset = result.nextOffset
            conversationSearchNextFromMessageId = 0
            conversationSearchUsesSecretMessages = true
        } else {
            let result = try await service.searchChatMessages(
                chatId: chatId,
                filter: nil,
                fromMessageId: conversationSearchNextFromMessageId,
                limit: 50,
                offset: 0,
                query: query,
                senderId: nil,
                topicId: nil,
            )
            messages = result.messages
            totalCount = result.totalCount
            conversationSearchNextFromMessageId = result.nextFromMessageId
            conversationSearchNextOffset = ""
        }

        guard !Task.isCancelled, generation == conversationSearchGeneration, openedChatId == chatId else { return }
        let existingIds = Set(conversationSearchResultIds)
        conversationSearchResultIds.append(contentsOf: messages.map(\.id).filter { !existingIds.contains($0) })
        conversationSearchTotalCount = totalCount >= 0 ? totalCount : conversationSearchResultIds.count
        isSearchingConversation = false
        conversationSearchError = nil

        if selectsFirstNewResult, conversationSearchResultIds.count > previousCount {
            selectConversationSearchResult(at: previousCount)
        } else if conversationSearchResultIds.isEmpty {
            conversationSearchSelectedIndex = nil
        }
    }

    private var isOpenedSecretChat: Bool {
        guard let openedChatType else {
            return false
        }
        if case .chatTypeSecret = openedChatType {
            return true
        }
        return false
    }

    private func selectConversationSearchResult(at index: Int) {
        guard let chatId = openedChatId, conversationSearchResultIds.indices.contains(index) else { return }
        conversationSearchSelectedIndex = index
        activateChat(chatId, messageId: conversationSearchResultIds[index])
    }

    private func clearConversationSearchResults() {
        conversationSearchResultIds = []
        conversationSearchSelectedIndex = nil
        conversationSearchTotalCount = 0
        conversationSearchError = nil
        conversationSearchNextFromMessageId = 0
        conversationSearchNextOffset = ""
        conversationSearchUsesSecretMessages = false
    }
}
