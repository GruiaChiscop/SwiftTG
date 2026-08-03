// TelegramConversationSearchStore.swift

import Foundation
import TDLibKit

@Observable final class TelegramConversationSearchStore {
    // MARK: Lifecycle

    init(service: any TelegramService) {
        self.service = service
    }

    deinit {
        searchTask?.cancel()
    }

    // MARK: Internal

    private(set) var isActive = false
    private(set) var isSearching = false
    var query = ""
    private(set) var resultIds = [Int64]()
    private(set) var selectedIndex: Int?
    private(set) var totalCount = 0
    private(set) var error: String?

    var status: String {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedQuery.isEmpty {
            return "Enter a search term"
        }
        if isSearching, resultIds.isEmpty {
            return "Searching"
        }
        if let error {
            return error
        }
        guard let selectedIndex else {
            return "No results"
        }
        return "\(selectedIndex + 1) of \(max(totalCount, resultIds.count))"
    }

    var canSelectOlderResult: Bool {
        guard let selectedIndex else { return false }
        return selectedIndex + 1 < resultIds.count || nextFromMessageId != 0 || !nextOffset.isEmpty
    }

    var canSelectNewerResult: Bool {
        guard let selectedIndex else { return false }
        return selectedIndex > 0
    }

    @MainActor func begin(
        chatId: Int64,
        isSecretChat: Bool,
        onSelect: @escaping @MainActor (Int64) -> Void,
    ) {
        if self.chatId != chatId {
            searchTask?.cancel()
            generation &+= 1
            clearResults()
            query = ""
        }
        self.chatId = chatId
        self.isSecretChat = isSecretChat
        self.onSelect = onSelect
        isActive = true
    }

    @MainActor func end() {
        searchTask?.cancel()
        searchTask = nil
        generation &+= 1
        isActive = false
        isSearching = false
        query = ""
        clearResults()
        chatId = nil
        onSelect = nil
    }

    @MainActor func queryDidChange() {
        searchTask?.cancel()
        generation &+= 1
        let requestedGeneration = generation
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        clearResults()

        guard !normalizedQuery.isEmpty else {
            isSearching = false
            return
        }

        isSearching = true
        searchTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: TelegramSearchPolicy.conversationQueryDebounce)
                guard let self, !Task.isCancelled, requestedGeneration == generation else { return }
                try await loadPage(
                    query: normalizedQuery,
                    generation: requestedGeneration,
                    selectsFirstNewResult: true,
                )
            } catch is CancellationError {
                return
            } catch {
                guard let self, requestedGeneration == generation else { return }
                isSearching = false
                self.error = error.localizedDescription
            }
        }
    }

    @MainActor func selectOlderResult() {
        guard let selectedIndex else { return }
        let nextIndex = selectedIndex + 1
        if nextIndex < resultIds.count {
            selectResult(at: nextIndex)
            return
        }
        guard nextFromMessageId != 0 || !nextOffset.isEmpty else { return }

        let requestedGeneration = generation
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        searchTask?.cancel()
        isSearching = true
        searchTask = Task { @MainActor [weak self] in
            do {
                guard let self else { return }
                try await loadPage(
                    query: normalizedQuery,
                    generation: requestedGeneration,
                    selectsFirstNewResult: true,
                )
            } catch is CancellationError {
                return
            } catch {
                guard let self, requestedGeneration == generation else { return }
                isSearching = false
                self.error = error.localizedDescription
            }
        }
    }

    @MainActor func selectNewerResult() {
        guard let selectedIndex, selectedIndex > 0 else { return }
        selectResult(at: selectedIndex - 1)
    }

    @MainActor func replaceService(_ service: any TelegramService) {
        end()
        self.service = service
    }

    // MARK: Private

    @ObservationIgnored private var service: any TelegramService
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var generation: UInt64 = 0
    @ObservationIgnored private var chatId: Int64?
    @ObservationIgnored private var isSecretChat = false
    @ObservationIgnored private var nextFromMessageId: Int64 = 0
    @ObservationIgnored private var nextOffset = ""
    @ObservationIgnored private var usesSecretMessages = false
    @ObservationIgnored private var onSelect: (@MainActor (Int64) -> Void)?

    @MainActor private func loadPage(
        query: String,
        generation requestedGeneration: UInt64,
        selectsFirstNewResult: Bool,
    ) async throws {
        guard let chatId else { return }
        let previousCount = resultIds.count
        let messages: [Message]
        let resolvedTotalCount: Int

        if usesSecretMessages || isSecretChat {
            let result = try await service.searchSecretMessages(
                chatId: chatId,
                filter: nil,
                limit: 50,
                offset: nextOffset,
                query: query,
            )
            messages = result.messages
            resolvedTotalCount = result.totalCount
            nextOffset = result.nextOffset
            nextFromMessageId = 0
            usesSecretMessages = true
        } else {
            let result = try await service.searchChatMessages(
                chatId: chatId,
                filter: nil,
                fromMessageId: nextFromMessageId,
                limit: 50,
                offset: 0,
                query: query,
                senderId: nil,
                topicId: nil,
            )
            messages = result.messages
            resolvedTotalCount = result.totalCount
            nextFromMessageId = result.nextFromMessageId
            nextOffset = ""
        }

        guard !Task.isCancelled, requestedGeneration == generation, self.chatId == chatId else { return }
        let existingIds = Set(resultIds)
        resultIds.append(contentsOf: messages.map(\.id).filter { !existingIds.contains($0) })
        totalCount = resolvedTotalCount >= 0 ? resolvedTotalCount : resultIds.count
        isSearching = false
        error = nil

        if selectsFirstNewResult, resultIds.count > previousCount {
            selectResult(at: previousCount)
        } else if resultIds.isEmpty {
            selectedIndex = nil
        }
    }

    @MainActor private func selectResult(at index: Int) {
        guard resultIds.indices.contains(index) else { return }
        selectedIndex = index
        onSelect?(resultIds[index])
    }

    private func clearResults() {
        resultIds = []
        selectedIndex = nil
        totalCount = 0
        error = nil
        nextFromMessageId = 0
        nextOffset = ""
        usesSecretMessages = false
    }
}
