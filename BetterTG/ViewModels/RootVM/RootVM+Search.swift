// RootVM+Search.swift

import Foundation
import TDLibKit

extension RootVM {
    func search(_ query: String, in chatList: ChatList) {
        searchTask?.cancel()
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            searchChatResults = []
            searchMessageResults = []
            searchMessageChatTitles = [:]
            searchResultChatsById = [:]
            isSearching = false
            return
        }

        searchGeneration &+= 1
        let generation = searchGeneration
        let service = service
        let knownChats = Dictionary(uniqueKeysWithValues: allChats.map { ($0.id, $0) })
        let messageChatList = TelegramSearchPolicy.messageChatListScope(for: chatList)
        isSearching = true

        searchTask = Task.background {
            try? await Task<Never, Never>.sleep(for: TelegramSearchPolicy.globalQueryDebounce)
            guard !Task.isCancelled else { return }

            async let foundChats = try? service.searchChats(limit: 50, query: normalized, typeFilter: nil)
            async let foundMessages = try? service.searchMessages(
                chatList: messageChatList,
                chatTypeFilter: nil,
                filter: nil,
                limit: 50,
                maxDate: 0,
                minDate: 0,
                offset: "",
                query: normalized,
            )
            let (chatResponse, messageResponse) = await (foundChats, foundMessages)
            guard !Task.isCancelled else { return }

            let searchedChatIds = chatResponse?.chatIds ?? []
            let messages = messageResponse?.messages ?? []
            var resolvedChats = knownChats
            var titles = [Int64: String]()
            for (chatId, chat) in knownChats {
                titles[chatId] = await chat.displayTitle
            }
            var idsToResolve = searchedChatIds
            for message in messages where !idsToResolve.contains(message.chatId) {
                idsToResolve.append(message.chatId)
            }

            for chatId in idsToResolve where resolvedChats[chatId] == nil {
                guard !Task.isCancelled,
                      let chat = try? await service.getChat(chatId: chatId),
                      let list = chat.positions.first?.list,
                      let customChat = await self.getCustomChat(from: chatId, for: list)
                else { continue }
                resolvedChats[chatId] = customChat
                titles[chatId] = await customChat.displayTitle
            }

            let chatResults = searchedChatIds.compactMap { resolvedChats[$0] }
            let messageResults = messages.filter { resolvedChats[$0.chatId] != nil }
            let finalTitles = titles
            let finalResolvedChats = resolvedChats
            await main {
                guard generation == self.searchGeneration, self.query == query else { return }
                self.searchChatResults = chatResults
                self.searchMessageResults = messageResults
                self.searchMessageChatTitles = finalTitles
                self.searchResultChatsById = finalResolvedChats
                self.isSearching = false
            }
        }
    }
}
