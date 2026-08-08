// RootVM+Search.swift

import Foundation
@preconcurrency import TDLibKit

extension RootVM {
    func search(_ query: String, in chatList: ChatList) {
        searchTask?.cancel()
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            searchChatResults = []
            searchGlobalChatResults = []
            searchMessageResults = []
            searchMessageChatTitles = [:]
            searchResultChatsById = [:]
            isSearching = false
            return
        }

        searchGeneration &+= 1
        let generation = searchGeneration
        let knownChats = Dictionary(uniqueKeysWithValues: allChats.map { ($0.id, $0) })
        let messageChatList = TelegramSearchPolicy.messageChatListScope(for: chatList)
        isSearching = true

        searchTask = Task.main {
            try? await Task<Never, Never>.sleep(for: TelegramSearchPolicy.globalQueryDebounce)
            guard !Task.isCancelled else { return }

            async let foundChats = try? self.service.searchChats(limit: 50, query: normalized, typeFilter: nil)
            async let foundMessages = try? self.service.searchMessages(
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
            // official app's own "Global Search" section. TDLib already excludes anything from
            // `searchChats`' own results, so no further de-duplication is needed on top.
            async let foundGlobalChats = try? self.service.searchPublicChats(query: normalized, typeFilter: nil)
            let (chatResponse, messageResponse, globalChatResponse) = await (
                foundChats,
                foundMessages,
                foundGlobalChats,
            )
            guard !Task.isCancelled else { return }

            let searchedChatIds = chatResponse?.chatIds ?? []
            let globalChatIds = globalChatResponse?.chatIds ?? []
            let messages = messageResponse?.messages ?? []
            var resolvedChats = knownChats
            var titles = [Int64: String]()
            for (chatId, chat) in knownChats {
                titles[chatId] = chat.displayTitle
            }
            var idsToResolve = searchedChatIds
            for message in messages where !idsToResolve.contains(message.chatId) {
                idsToResolve.append(message.chatId)
            }

            for chatId in idsToResolve where resolvedChats[chatId] == nil {
                guard !Task.isCancelled,
                      let chat = try? await self.service.getChat(chatId: chatId),
                      let list = chat.positions.first?.list,
                      let customChat = await self.getCustomChat(from: chatId, for: list)
                else { continue }
                resolvedChats[chatId] = customChat
                titles[chatId] = customChat.displayTitle
            }

            var globalResolvedChats = [Int64: CustomChat]()
            for chatId in globalChatIds where resolvedChats[chatId] == nil {
                guard !Task.isCancelled, let customChat = await self.getCustomChat(from: chatId) else { continue }
                globalResolvedChats[chatId] = customChat
            }

            let chatResults = searchedChatIds.compactMap { resolvedChats[$0] }
            let globalChatResults = globalChatIds.compactMap { globalResolvedChats[$0] }
            let messageResults = messages.filter { resolvedChats[$0.chatId] != nil }
            guard generation == self.searchGeneration, self.query == query else { return }
            self.searchChatResults = chatResults
            self.searchGlobalChatResults = globalChatResults
            self.searchMessageResults = messageResults
            self.searchMessageChatTitles = titles
            self.searchResultChatsById = resolvedChats
            self.isSearching = false
        }
    }
}
