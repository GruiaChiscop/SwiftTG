// MacSearch.swift

import Foundation
import TDLibKit

// MARK: - MacSearchResultID

enum MacSearchResultID: Hashable {
    case chat(Int64)
    case message(chatId: Int64, messageId: Int64)
}

// MARK: - MacChatSearchResult

struct MacChatSearchResult: Identifiable {
    let chat: ChatListItemState
    let chatList: ChatList

    var chatId: Int64 { chat.chatId }
    var id: MacSearchResultID { .chat(chat.chatId) }
}

// MARK: - MacMessageSearchResult

struct MacMessageSearchResult: Identifiable {
    let message: Message
    let chatTitle: String

    var id: MacSearchResultID {
        .message(chatId: message.chatId, messageId: message.id)
    }
}

extension MacSessionModel {
    func setSearchQuery(_ query: String) {
        searchQuery = query
        focusedSearchResult = nil
        searchTask?.cancel()

        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            chatSearchResults = []
            globalChatSearchResults = []
            messageSearchResults = []
            isSearching = false
            return
        }

        searchGeneration &+= 1
        let generation = searchGeneration
        let service = service
        let searchedChatList = selectedChatList
        let messageChatList = TelegramSearchPolicy.messageChatListScope(for: searchedChatList)
        isSearching = true
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: TelegramSearchPolicy.globalQueryDebounce)
            guard !Task.isCancelled else { return }

            async let chatResponse = try? service.searchChats(limit: 50, query: normalized, typeFilter: nil)
            async let messageResponse = try? service.searchMessages(
                chatList: messageChatList,
                chatTypeFilter: nil,
                filter: nil,
                limit: 50,
                maxDate: 0,
                minDate: 0,
                offset: "",
                query: normalized,
            )
            // Unlike `searchChats` (offline, known chats only), `searchPublicChats` reaches the
            // server for public chats/users not already in the chat list or contacts - matches the
            // official app's own "Global Search" section (and the same addition already made to
            // iOS's RootVM+Search.swift). TDLib already excludes anything `searchChats` itself would
            // return, so no further de-duplication is needed on top.
            async let globalChatResponse = try? service.searchPublicChats(query: normalized, typeFilter: nil)
            let (foundChats, foundMessages, foundGlobalChats) = await (
                chatResponse,
                messageResponse,
                globalChatResponse,
            )
            guard !Task.isCancelled else { return }

            let chatIds = foundChats?.chatIds ?? []
            var chatResults = [MacChatSearchResult]()
            for chatId in chatIds {
                guard !Task.isCancelled else { return }
                if let known = self?.chatList.items[chatId] {
                    chatResults.append(.init(
                        chat: known,
                        chatList: known.position(in: searchedChatList) == nil
                            ? known.positions.first?.list ?? searchedChatList
                            : searchedChatList,
                    ))
                } else if let chat = try? await service.getChat(chatId: chatId) {
                    let membership = await service.resolveMembership(for: chat)
                    chatResults.append(.init(
                        chat: ChatListItemState(chat, membership: membership),
                        chatList: chat.positions.first?.list ?? searchedChatList,
                    ))
                }
            }

            let globalChatIds = foundGlobalChats?.chatIds ?? []
            var globalChatResults = [MacChatSearchResult]()
            for chatId in globalChatIds where self?.chatList.items[chatId] == nil {
                guard !Task.isCancelled else { return }
                guard let chat = try? await service.getChat(chatId: chatId) else { continue }
                let membership = await service.resolveMembership(for: chat)
                globalChatResults.append(.init(
                    chat: ChatListItemState(chat, membership: membership),
                    chatList: chat.positions.first?.list ?? searchedChatList,
                ))
            }

            let messages = foundMessages?.messages ?? []
            var titles = [Int64: String]()
            var messageResults = [MacMessageSearchResult]()
            for message in messages {
                guard !Task.isCancelled else { return }
                let title: String
                if let cached = titles[message.chatId] {
                    title = cached
                } else if let known = self?.chatList.items[message.chatId]?.displayTitle {
                    title = known
                    titles[message.chatId] = known
                } else if let chat = try? await service.getChat(chatId: message.chatId) {
                    let resolvedTitle = ChatListItemState(chat, membership: nil).displayTitle
                    title = resolvedTitle
                    titles[message.chatId] = resolvedTitle
                } else {
                    title = "Chat"
                }
                messageResults.append(.init(message: message, chatTitle: title))
            }

            guard let self, generation == searchGeneration, searchQuery == query else { return }
            chatSearchResults = chatResults
            globalChatSearchResults = globalChatResults
            messageSearchResults = messageResults
            isSearching = false
        }
    }

    func activateFocusedSearchResult() {
        guard let focusedSearchResult else { return }
        switch focusedSearchResult {
        case .chat(let chatId):
            activateChat(chatId)
        case .message(let chatId, let messageId):
            activateChat(chatId, messageId: messageId)
        }
    }
}
