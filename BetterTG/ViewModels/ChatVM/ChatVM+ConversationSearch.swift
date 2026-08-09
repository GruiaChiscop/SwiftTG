// ChatVM+ConversationSearch.swift

import TDLibKit

extension ChatVM {
    var isConversationSearchActive: Bool { conversationSearch.isActive }
    var isSearchingConversation: Bool { conversationSearch.isSearching }

    var conversationSearchQuery: String {
        get { conversationSearch.query }
        set { conversationSearch.query = newValue }
    }

    var conversationSearchResultIds: [Int64] { conversationSearch.resultIds }
    var conversationSearchSelectedIndex: Int? { conversationSearch.selectedIndex }
    var conversationSearchTotalCount: Int { conversationSearch.totalCount }
    var conversationSearchError: String? { conversationSearch.error }
    var conversationSearchStatus: String { conversationSearch.status }
    var canSelectOlderConversationSearchResult: Bool { conversationSearch.canSelectOlderResult }
    var canSelectNewerConversationSearchResult: Bool { conversationSearch.canSelectNewerResult }

    @MainActor func beginConversationSearch() {
        conversationSearch.begin(
            chatId: customChat.chat.id,
            isSecretChat: isSecretChat,
            topicId: messageTopic,
            onSelect: { [weak self] messageId in
                self?.navigateToMessage(id: messageId)
            },
        )
    }

    @MainActor func endConversationSearch() {
        conversationSearch.end()
    }

    @MainActor func conversationSearchQueryDidChange() {
        conversationSearch.queryDidChange()
    }

    @MainActor func selectOlderConversationSearchResult() {
        conversationSearch.selectOlderResult()
    }

    @MainActor func selectNewerConversationSearchResult() {
        conversationSearch.selectNewerResult()
    }

    private var isSecretChat: Bool {
        if case .chatTypeSecret = customChat.chat.type {
            return true
        }
        return false
    }
}
