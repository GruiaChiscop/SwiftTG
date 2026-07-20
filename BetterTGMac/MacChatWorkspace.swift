// MacChatWorkspace.swift

import SwiftUI

struct MacChatWorkspace: View {
    // MARK: Internal

    @Bindable var model: MacSessionModel

    var body: some View {
        NavigationSplitView {
            MacChatSidebar(model: model)
        } detail: {
            MacChatDetail(model: model)
        }
        .navigationTitle("BetterTG")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            TelegramAudioPlayerBar()
        }
        .alert(
            "Action Failed",
            isPresented: Binding(
                get: { model.messageActionError != nil },
                set: {
                    if !$0 {
                        model.messageActionError = nil
                    }
                },
            ),
        ) {
            Button("OK") { model.messageActionError = nil }
        } message: {
            Text(model.messageActionError ?? "Unknown error")
        }
    }
}

// MARK: - Isolated navigation columns

/// Keeping the sidebar and detail in separate observation scopes prevents an `openedChatId`
/// change from rebuilding the entire chat list, and a `focusedChatId` change from reconstructing
/// the conversation hierarchy.
private struct MacChatSidebar: View {
    @Bindable var model: MacSessionModel

    var body: some View {
        VStack(spacing: 0) {
            MacChatFolderPicker(model: model)
            Divider()
            if model.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                chatList
            } else {
                searchResults
            }
        }
        .searchable(
            text: Binding(
                get: { model.searchQuery },
                set: { model.setSearchQuery($0) },
            ),
            prompt: "Search chats and messages",
        )
        .navigationSplitViewColumnWidth(min: 250, ideal: 310, max: 420)
    }

    // MARK: Private

    private var chatList: some View {
        List(selection: $model.focusedChatId) {
            if model.chatItems.isEmpty, model.isLoadingChats {
                HStack {
                    Spacer()
                    ProgressView("Loading chats…")
                    Spacer()
                }
                .padding()
            }

            ForEach(model.chatItems, id: \.chatId) { chat in
                MacChatRow(
                    model: model,
                    chat: chat,
                    chatList: model.selectedChatList,
                    isOpen: model.openedChatId == chat.chatId,
                )
                .tag(chat.chatId)
                .contentShape(Rectangle())
                .onTapGesture { model.activateChat(chat.chatId) }
                .accessibilityAction { model.activateChat(chat.chatId) }
            }
        }
        .onKeyPress(.return) {
            model.activateFocusedChat()
            return .handled
        }
        .onKeyPress(.space) {
            model.activateFocusedChat()
            return .handled
        }
        .overlay {
            if model.chatItems.isEmpty, !model.isLoadingChats {
                ContentUnavailableView("No Chats", systemImage: "tray")
            }
        }
    }

    private var searchResults: some View {
        List(selection: $model.focusedSearchResult) {
            if !model.chatSearchResults.isEmpty {
                Section {
                    ForEach(model.chatSearchResults) { result in
                        MacChatRow(
                            model: model,
                            chat: model.chatList.items[result.chatId] ?? result.chat,
                            chatList: result.chatList,
                            isOpen: model.openedChatId == result.chatId,
                        )
                        .tag(result.id)
                        .contentShape(Rectangle())
                        .onTapGesture { model.activateChat(result.chatId) }
                    }
                } header: {
                    Text("Chats (\(model.chatSearchResults.count))")
                        .font(.headline)
                        .accessibilityLabel("Chats, \(model.chatSearchResults.count) found")
                        .accessibilityAddTraits(.isHeader)
                }
            }

            if !model.messageSearchResults.isEmpty {
                Section {
                    ForEach(model.messageSearchResults) { result in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(result.chatTitle)
                                    .fontWeight(.semibold)
                                Spacer()
                                Text(
                                    Date(timeIntervalSince1970: TimeInterval(result.message.date)),
                                    format: .dateTime.day().month().hour().minute(),
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            Text(macMessageText(result.message))
                                .lineLimit(2)
                                .foregroundStyle(.secondary)
                        }
                        .tag(result.id)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            model.activateChat(result.message.chatId, messageId: result.message.id)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(
                            "\(result.chatTitle), \(macMessageText(result.message)), sent "
                                + Date(timeIntervalSince1970: TimeInterval(result.message.date))
                                .formatted(date: .abbreviated, time: .shortened),
                        )
                        .accessibilityHint("Press Return or Space to open this message")
                    }
                } header: {
                    Text("Messages (\(model.messageSearchResults.count))")
                        .font(.headline)
                        .accessibilityLabel("Messages, \(model.messageSearchResults.count) found")
                        .accessibilityAddTraits(.isHeader)
                }
            }

            if model.isSearching {
                ProgressView("Searching…")
                    .frame(maxWidth: .infinity)
            }
        }
        .onKeyPress(.return) {
            model.activateFocusedSearchResult()
            return .handled
        }
        .onKeyPress(.space) {
            model.activateFocusedSearchResult()
            return .handled
        }
        .overlay {
            if !model.isSearching,
               model.chatSearchResults.isEmpty,
               model.messageSearchResults.isEmpty
            {
                ContentUnavailableView.search(text: model.searchQuery)
            }
        }
    }
}

/// Deliberately has no `.id(chat.chatId)`: `MacMessageTable.Coordinator` already handles chat
/// changes and can cheaply reuse its AppKit table. Re-keying this subtree destroyed and rebuilt
/// every hosted row on each click.
private struct MacChatDetail: View {
    @Bindable var model: MacSessionModel

    var body: some View {
        if let chat = model.openedChat {
            MacConversationView(model: model, chat: chat)
        } else {
            ContentUnavailableView(
                "Select a Chat",
                systemImage: "bubble.left.and.bubble.right",
                description: Text("Select a chat"),
            )
        }
    }
}
