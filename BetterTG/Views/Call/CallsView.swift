// CallsView.swift

import SwiftUI
@preconcurrency import TDLibKit

// MARK: - TelegramCallHistoryItem

private struct TelegramCallHistoryItem: Identifiable {
    let message: Message
    let chat: Chat
    let user: User

    var id: String { "\(message.chatId):\(message.id)" }

    var isVideo: Bool {
        switch message.content {
        case .messageCall(let content): content.isVideo
        case .messageGroupCall(let content): content.isVideo
        default: false
        }
    }

    var isConference: Bool {
        if case .messageGroupCall = message.content {
            return true
        }
        return false
    }

    var status: String {
        telegramMessageContentDescription(message)
    }
}

// MARK: - CallsView

struct CallsView: View {
    // MARK: Lifecycle

    init(service: any TelegramService) {
        self.service = service
    }

    // MARK: Internal

    var body: some View {
        List {
            ForEach(items) { item in
                callRow(item)
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            delete(item)
                        }
                    }
                    .onAppear {
                        guard item.id == items.last?.id else { return }
                        Task { await loadMore() }
                    }
            }
        }
        .overlay {
            if isLoading, items.isEmpty {
                ProgressView("Loading calls…")
            } else if items.isEmpty {
                ContentUnavailableView(
                    filter == .missed ? "No Missed Calls" : "No Calls",
                    systemImage: "phone",
                    description: Text(
                        filter == .missed
                            ? "Missed and declined calls will appear here."
                            : "Your recent calls will appear here.",
                    ),
                )
            }
        }
        .navigationTitle("Calls")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top, spacing: 0) {
            Picker("Call Filter", selection: $filter) {
                Text("All").tag(Filter.all)
                Text("Missed").tag(Filter.missed)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 8)
            .background(.bar)
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if !items.isEmpty {
                    Button("Clear", role: .destructive) {
                        showsClearConfirmation = true
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu("New Call", systemImage: "phone.badge.plus") {
                    Button("New Call", systemImage: "person.badge.plus") {
                        showsContactPicker = true
                    }
                    Button("New Call Link", systemImage: "link") {
                        showsNewCallLink = true
                    }
                }
            }
        }
        .task(id: filter) { await reload() }
        .refreshable { await reload() }
        .onReceive(service.updatePublisher) { update in
            switch update {
            case .updateDeleteMessages, .updateMessageContent, .updateNewMessage:
                scheduleReload()
            default:
                break
            }
        }
        .alert("Clear Call History?", isPresented: $showsClearConfirmation) {
            Button("Clear for Me", role: .destructive) {
                Task { await clearHistory() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All call entries will be removed from this device and your Telegram account.")
        }
        .sheet(isPresented: $showsContactPicker) {
            NavigationStack {
                CallContactPicker(service: service)
            }
        }
        .sheet(isPresented: $showsNewCallLink) {
            NavigationStack {
                NewCallLinkView(service: service)
            }
        }
        .navigationDestination(item: $pushedChat) { customChat in
            ChatView(customChat: customChat, backButtonTitleOverride: "Calls")
        }
        .alert("Calls Error", isPresented: errorIsPresented) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Private

    private enum Filter: Hashable {
        case all
        case missed
    }

    @Bindable private var rootVM = RootVM.shared
    @State private var errorMessage: String?
    @State private var filter = Filter.all
    @State private var isLoading = false
    @State private var items = [TelegramCallHistoryItem]()
    @State private var nextOffset = ""
    @State private var pushedChat: CustomChat?
    @State private var reloadTask: Task<Void, Never>?
    @State private var showsClearConfirmation = false
    @State private var showsContactPicker = false
    @State private var showsNewCallLink = false

    private let service: any TelegramService

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

    private func callRow(_ item: TelegramCallHistoryItem) -> some View {
        Button {
            activate(item)
        } label: {
            HStack(spacing: 12) {
                ProfileImageView(
                    photo: item.user.profilePhoto?.small,
                    minithumbnail: item.user.profilePhoto?.minithumbnail,
                    title: telegramUserDisplayName(item.user),
                    userId: item.user.id,
                )
                .frame(width: 48, height: 48)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(telegramUserDisplayName(item.user))
                        .font(.body.weight(.semibold))
                    HStack(spacing: 4) {
                        Image(systemName: directionImage(for: item.message))
                            .foregroundStyle(isMissed(item.message) ? .red : .green)
                        Text(item.status)
                        Text("·")
                        Text(telegramChatListTimestamp(item.message.date))
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: item.isVideo ? "video.fill" : "phone.fill")
                    .foregroundStyle(.tint)
                    .frame(width: 36, height: 36)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Message", systemImage: "message") {
                Task { await openChat(item) }
            }
            Button(item.isVideo ? "Video Call" : "Call", systemImage: item.isVideo ? "video" : "phone") {
                activate(item)
            }
        }
    }

    @MainActor private func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let found = try await service.searchCallMessages(
                limit: 100,
                offset: "",
                onlyMissed: filter == .missed,
            )
            guard !Task.isCancelled else { return }
            items = await resolve(found.messages)
            nextOffset = found.nextOffset
        } catch is CancellationError {
            return
        } catch {
            errorMessage = telegramErrorDescription(error)
        }
    }

    @MainActor private func loadMore() async {
        guard !isLoading, !nextOffset.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let found = try await service.searchCallMessages(
                limit: 100,
                offset: nextOffset,
                onlyMissed: filter == .missed,
            )
            guard !Task.isCancelled else { return }
            let loaded = await resolve(found.messages)
            let existingIds = Set(items.map(\.id))
            items.append(contentsOf: loaded.filter { !existingIds.contains($0.id) })
            nextOffset = found.nextOffset
        } catch is CancellationError {
            return
        } catch {
            errorMessage = telegramErrorDescription(error)
        }
    }

    private func resolve(_ messages: [Message]) async -> [TelegramCallHistoryItem] {
        await messages.concurrentCompactMap { message in
            guard let chat = try? await service.getChat(chatId: message.chatId) else { return nil }
            let userId: Int64
            switch chat.type {
            case .chatTypePrivate(let value):
                userId = value.userId
            case .chatTypeSecret(let value):
                userId = value.userId
            case .chatTypeBasicGroup, .chatTypeSupergroup:
                return nil
            }
            guard let user = try? await service.getUser(userId: userId) else { return nil }
            return TelegramCallHistoryItem(message: message, chat: chat, user: user)
        }
    }

    private func activate(_ item: TelegramCallHistoryItem) {
        if item.isConference {
            Task { @MainActor in
                let session = TelegramCallSession.shared
                if session.groupCallCoordinator != nil {
                    session.restoreCallView()
                } else {
                    let joined = await session.joinConference(
                        chatId: item.message.chatId,
                        messageId: item.message.id,
                        isMuted: false,
                    )
                    if !joined {
                        errorMessage = "This group call is no longer available, or another call is already active."
                    }
                }
            }
            return
        }
        CallKitManager.shared.startOutgoingCall(
            userId: item.user.id,
            displayName: telegramUserDisplayName(item.user),
            isVideo: item.isVideo,
            onMicrophonePermissionDenied: {
                errorMessage = "Microphone access is required to make calls."
            },
            onCameraPermissionDenied: {
                errorMessage = "Camera access is required to start video calls."
            },
        )
    }

    @MainActor private func openChat(_ item: TelegramCallHistoryItem) async {
        pushedChat = await rootVM.getCustomChat(from: item.chat.id)
        if pushedChat == nil {
            errorMessage = "The conversation couldn't be opened."
        }
    }

    private func delete(_ item: TelegramCallHistoryItem) {
        items.removeAll { $0.id == item.id }
        Task {
            do {
                _ = try await service.deleteMessages(
                    chatId: item.message.chatId,
                    messageIds: [item.message.id],
                    revoke: false,
                )
            } catch {
                errorMessage = telegramErrorDescription(error)
                await reload()
            }
        }
    }

    @MainActor private func clearHistory() async {
        do {
            _ = try await service.deleteAllCallMessages(revoke: false)
            items = []
            nextOffset = ""
        } catch {
            errorMessage = telegramErrorDescription(error)
        }
    }

    private func scheduleReload() {
        reloadTask?.cancel()
        reloadTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await reload()
        }
    }

    private func directionImage(for message: Message) -> String {
        message.isOutgoing ? "arrow.up.right" : "arrow.down.left"
    }

    private func isMissed(_ message: Message) -> Bool {
        switch message.content {
        case .messageCall(let content):
            switch content.discardReason {
            case .callDiscardReasonDeclined, .callDiscardReasonDisconnected, .callDiscardReasonMissed:
                true
            case .callDiscardReasonEmpty, .callDiscardReasonHungUp, .callDiscardReasonUpgradeToGroupCall:
                false
            }
        case .messageGroupCall(let content):
            TelegramGroupCallMessagePresentation(
                content: content,
                isOutgoing: message.isOutgoing,
                messageDate: message.date,
            ).isSuccessful == false
        default:
            false
        }
    }
}

// MARK: - CallContactPicker

private struct CallContactPicker: View {
    // MARK: Lifecycle

    init(service: any TelegramService) {
        self.service = service
    }

    // MARK: Internal

    var body: some View {
        List(filteredUsers) { user in
            HStack(spacing: 12) {
                ProfileImageView(
                    photo: user.profilePhoto?.small,
                    minithumbnail: user.profilePhoto?.minithumbnail,
                    title: telegramUserDisplayName(user),
                    userId: user.id,
                )
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)

                Text(telegramUserDisplayName(user))
                Spacer()
                Button("Call", systemImage: "phone.fill") { start(user, isVideo: false) }
                    .labelStyle(.iconOnly)
                Button("Video Call", systemImage: "video.fill") { start(user, isVideo: true) }
                    .labelStyle(.iconOnly)
            }
        }
        .overlay {
            if isLoading {
                ProgressView("Loading contacts…")
            } else if filteredUsers.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .navigationTitle("New Call")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search contacts")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .task { await load() }
        .alert("Call Failed", isPresented: errorIsPresented) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var query = ""
    @State private var users = [User]()

    private let service: any TelegramService

    private var filteredUsers: [User] {
        guard !query.isEmpty else { return users }
        return users.filter {
            telegramUserDisplayName($0).localizedCaseInsensitiveContains(query)
        }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: {
                if !$0 {
                    errorMessage = nil
                }
            },
        )
    }

    @MainActor private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let contacts = try await service.getContacts()
            users = await contacts.userIds
                .concurrentCompactMap {
                    try? await service.getUser(userId: $0)
                }
                .sorted {
                    telegramUserDisplayName($0)
                        .localizedStandardCompare(telegramUserDisplayName($1)) == .orderedAscending
                }
        } catch {
            errorMessage = telegramErrorDescription(error)
        }
    }

    private func start(_ user: User, isVideo: Bool) {
        CallKitManager.shared.startOutgoingCall(
            userId: user.id,
            displayName: telegramUserDisplayName(user),
            isVideo: isVideo,
            onMicrophonePermissionDenied: {
                errorMessage = "Microphone access is required to make calls."
            },
            onCameraPermissionDenied: {
                errorMessage = "Camera access is required to start video calls."
            },
            completion: { started in
                if started {
                    dismiss()
                } else if errorMessage == nil {
                    errorMessage = "Another call is already active, or the call couldn't be started."
                }
            },
        )
    }
}
