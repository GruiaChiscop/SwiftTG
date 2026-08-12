// TelegramPrivacyExceptions.swift

import SwiftUI
@preconcurrency import TDLibKit

// MARK: - TelegramPrivacyExceptionSelection

struct TelegramPrivacyExceptionSelection: Equatable {
    var userIds: Set<Int64>
    var chatIds: Set<Int64>
}

// MARK: - TelegramPrivacyExceptionPicker

struct TelegramPrivacyExceptionPicker: View {
    // MARK: Lifecycle

    init(
        service: any TelegramService,
        title: String,
        selection: TelegramPrivacyExceptionSelection,
        onDone: @escaping (TelegramPrivacyExceptionSelection) -> Void,
    ) {
        self.service = service
        self.title = title
        _selection = State(initialValue: selection)
        self.onDone = onDone
    }

    // MARK: Internal

    var body: some View {
        NavigationStack {
            List {
                if !filteredUsers.isEmpty {
                    Section("Contacts") {
                        ForEach(filteredUsers) { user in
                            Button {
                                toggleUser(user.id)
                            } label: {
                                selectionLabel(
                                    telegramUserDisplayName(user),
                                    isSelected: selection.userIds.contains(user.id),
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(selection.userIds.contains(user.id) ? [.isSelected] : [])
                        }
                    }
                }

                if !filteredChats.isEmpty {
                    Section("Groups") {
                        ForEach(filteredChats) { chat in
                            Button {
                                toggleChat(chat.id)
                            } label: {
                                selectionLabel(chat.title, isSelected: selection.chatIds.contains(chat.id))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(selection.chatIds.contains(chat.id) ? [.isSelected] : [])
                        }
                    }
                }
            }
            .overlay {
                if isLoading, users.isEmpty, chats.isEmpty {
                    ProgressView("Loading People and Groups…")
                } else if !isLoading, filteredUsers.isEmpty, filteredChats.isEmpty {
                    if query.isEmpty {
                        ContentUnavailableView(
                            "No People or Groups",
                            systemImage: "person.crop.circle.badge.xmark",
                            description: Text("Your Telegram contacts and groups will appear here."),
                        )
                    } else {
                        ContentUnavailableView.search(text: query)
                    }
                }
            }
            .searchable(text: $query, prompt: "Search People and Groups")
            .navigationTitle(title)
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            onDone(selection)
                            dismiss()
                        }
                    }
                }
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 440)
        #endif
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            await loadPeers()
        }
        .alert("Couldn't Load Privacy Exceptions", isPresented: errorIsPresented) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @State private var chats = [Chat]()
    @State private var errorMessage: String?
    @State private var hasLoaded = false
    @State private var isLoading = false
    @State private var query = ""
    @State private var selection: TelegramPrivacyExceptionSelection
    @State private var users = [User]()

    private let onDone: (TelegramPrivacyExceptionSelection) -> Void
    private let service: any TelegramService
    private let title: String

    private var filteredChats: [Chat] {
        guard !query.isEmpty else { return chats }
        return chats.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    private var filteredUsers: [User] {
        guard !query.isEmpty else { return users }
        return users.filter { user in
            let searchableText = ([telegramUserDisplayName(user)] + (user.usernames?.activeUsernames ?? []))
                .joined(separator: " ")
            return searchableText.localizedCaseInsensitiveContains(query)
        }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    errorMessage = nil
                }
            },
        )
    }

    private func selectionLabel(_ title: String, isSelected: Bool) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.primary)
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
    }

    private func toggleChat(_ chatId: Int64) {
        if selection.chatIds.contains(chatId) {
            selection.chatIds.remove(chatId)
        } else {
            selection.chatIds.insert(chatId)
        }
    }

    private func toggleUser(_ userId: Int64) {
        if selection.userIds.contains(userId) {
            selection.userIds.remove(userId)
        } else {
            selection.userIds.insert(userId)
        }
    }

    @MainActor private func loadPeers() async {
        isLoading = true
        defer { isLoading = false }

        let contacts = try? await service.getContacts()
        let userIds = Set(contacts?.userIds ?? []).union(selection.userIds)
        users = await userIds
            .concurrentCompactMap { try? await service.getUser(userId: $0) }
            .sorted {
                telegramUserDisplayName($0)
                    .localizedStandardCompare(telegramUserDisplayName($1)) == .orderedAscending
            }

        let recentChats = try? await service.getChats(chatList: .chatListMain, limit: 200)
        let chatIds = Set(recentChats?.chatIds ?? []).union(selection.chatIds)
        chats = await chatIds
            .concurrentCompactMap { try? await service.getChat(chatId: $0) }
            .filter { chat in
                switch chat.type {
                case .chatTypeBasicGroup:
                    true
                case .chatTypeSupergroup(let value):
                    !value.isChannel
                default:
                    false
                }
            }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

        if contacts == nil, recentChats == nil, users.isEmpty, chats.isEmpty {
            errorMessage = "Telegram couldn't load your contacts or groups."
        }
    }
}
