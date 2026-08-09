// MacSessionModel+ConversationSearch.swift

import TDLibKit

extension MacSessionModel {
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

    func beginConversationSearch() {
        guard let chatId = openedChatId else { return }
        conversationSearch.begin(
            chatId: chatId,
            isSecretChat: isOpenedSecretChat,
            topicId: openedTopic,
            onSelect: { [weak self] messageId in
                guard let self, openedChatId == chatId else { return }
                activateChat(chatId, messageId: messageId)
            },
        )
    }

    func endConversationSearch() {
        conversationSearch.end()
    }

    func conversationSearchQueryDidChange() {
        conversationSearch.queryDidChange()
    }

    func selectOlderConversationSearchResult() {
        conversationSearch.selectOlderResult()
    }

    func selectNewerConversationSearchResult() {
        conversationSearch.selectNewerResult()
    }

    private var isOpenedSecretChat: Bool {
        guard let openedChatType else { return false }
        if case .chatTypeSecret = openedChatType {
            return true
        }
        return false
    }
}
