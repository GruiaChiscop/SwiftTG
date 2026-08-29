// CallsView.swift

import SwiftUI
@preconcurrency import TDLibKit

// MARK: - CallHistoryParticipant

private struct CallHistoryParticipant: Identifiable {
    let id: Int64
    let title: String
    let photo: File?
    let minithumbnail: Minithumbnail?
}

// MARK: - CallHistoryGroup

/// A run of consecutive calls with the same peer, collapsed into one row - matching Telegram-iOS's
/// grouping of back-to-back calls with a `(N)` count.
private struct CallHistoryGroup: Identifiable {
    // MARK: Internal

    let entries: [TelegramCallHistoryEntry]
    let chat: Chat
    let user: User
    /// Up to three other conference participants, for the stacked avatar.
    let participants: [CallHistoryParticipant]

    var id: Int64 { top.id }
    var top: TelegramCallHistoryEntry { entries[0] }
    var count: Int { entries.count }
    var isConference: Bool { top.isConference }
    var isVideo: Bool { entries.contains(where: \.isVideo) }
    var hasMissed: Bool { entries.contains(where: \.isMissed) }
    var hasIncoming: Bool { entries.contains(where: { !$0.isOutgoing }) }
    var hasOutgoing: Bool { entries.contains(where: \.isOutgoing) }
    var duration: Int { entries.first(where: { $0.duration > 1 })?.duration ?? 0 }

    var title: String { telegramUserDisplayName(user) }

    /// Compact status text: "Missed", "Incoming (2:05)", "Outgoing, Incoming", …
    var statusText: String {
        if hasMissed {
            return "Missed"
        }
        if hasIncoming, hasOutgoing {
            return "Outgoing, Incoming"
        }
        let direction = hasIncoming ? "Incoming" : "Outgoing"
        if duration > 1 {
            return "\(direction) (\(telegramCallDurationClock(duration)))"
        }
        return direction
    }

    var accessibilityLabel: String {
        var parts = [title]
        if count > 1 {
            parts.append("\(count) calls")
        }
        parts.append(spokenStatus)
        parts.append(telegramCallListTimestamp(top.date))
        return parts.joined(separator: ", ")
    }

    // MARK: Private

    private var spokenStatus: String {
        let kind = isConference ? "group call" : "call"
        if hasMissed {
            return isVideo ? "Missed video \(kind)" : "Missed \(kind)"
        }
        if hasIncoming, hasOutgoing {
            return "Outgoing and incoming \(kind)s"
        }
        let direction = hasIncoming ? "Incoming" : "Outgoing"
        let base = isVideo ? "\(direction) video \(kind)" : "\(direction) \(kind)"
        return duration > 1 ? "\(base), \(telegramSpokenDuration(duration))" : base
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
            if let activeConferenceTitle {
                Section {
                    Button {
                        TelegramCallSession.shared.restoreCallView()
                    } label: {
                        Label("Return to \(activeConferenceTitle)", systemImage: "phone.connection.fill")
                            .foregroundStyle(.green)
                    }
                    .buttonStyle(.plain)
                }
            }

            Section("Recent Calls") {
                ForEach(groups) { group in
                    callRow(group)
                        .swipeActions {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                delete(group)
                            }
                        }
                        .onAppear {
                            guard group.id == groups.last?.id else { return }
                            Task { await loadMore() }
                        }
                }
            }
        }
        .overlay {
            if isLoading, groups.isEmpty {
                ProgressView("Loading calls…")
            } else if groups.isEmpty {
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
                if !groups.isEmpty {
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
        .sheet(item: $detailGroup) { group in
            CallDetailView(
                title: group.title,
                userId: group.user.id,
                photo: group.user.profilePhoto?.small,
                minithumbnail: group.user.profilePhoto?.minithumbnail,
                entries: group.entries,
                onCallBack: { isVideo in
                    detailGroup = nil
                    activate(group, videoOverride: isVideo)
                },
                onMessage: {
                    detailGroup = nil
                    Task { await openChat(group) }
                },
            )
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
    @State private var session = TelegramCallSession.shared
    @State private var errorMessage: String?
    @State private var filter = Filter.all
    @State private var isLoading = false
    @State private var groups = [CallHistoryGroup]()
    @State private var nextOffset = ""
    @State private var detailGroup: CallHistoryGroup?
    @State private var pushedChat: CustomChat?
    @State private var reloadTask: Task<Void, Never>?
    @State private var showsClearConfirmation = false
    @State private var showsContactPicker = false
    @State private var showsNewCallLink = false

    private let service: any TelegramService

    private var activeConferenceTitle: String? {
        guard session.groupCallCoordinator != nil else { return nil }
        return session.conferenceDisplayTitle
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

    private func callRow(_ group: CallHistoryGroup) -> some View {
        HStack(spacing: 8) {
            Button {
                activate(group)
            } label: {
                HStack(spacing: 12) {
                    callAvatar(group)
                        .frame(width: 48, height: 48)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(group.title)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.primary)
                            if group.count > 1 {
                                Text("(\(group.count))")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        HStack(spacing: 4) {
                            if group.hasOutgoing, !group.hasIncoming, !group.hasMissed {
                                Image(systemName: "arrow.up.right")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Text(group.statusText)
                                .foregroundStyle(group.hasMissed ? Color.red : Color.secondary)
                            Text("·")
                                .foregroundStyle(.secondary)
                            Text(telegramCallListTimestamp(group.top.date))
                                .foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                        .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: group.isVideo ? "video" : "phone")
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(group.accessibilityLabel)
            .accessibilityActions {
                Button("Message") {
                    Task { await openChat(group) }
                }
                Button("Details") {
                    detailGroup = group
                }
            }
            .contextMenu {
                Button("Message", systemImage: "message") {
                    Task { await openChat(group) }
                }
            }

            Button {
                detailGroup = group
            } label: {
                Image(systemName: "info.circle")
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder private func callAvatar(_ group: CallHistoryGroup) -> some View {
        if group.isConference, !group.participants.isEmpty {
            ZStack {
                ForEach(Array(group.participants.prefix(3).enumerated()), id: \.element.id) { index, participant in
                    ProfileImageView(
                        photo: participant.photo,
                        minithumbnail: participant.minithumbnail,
                        title: participant.title,
                        userId: participant.id,
                    )
                    .frame(width: 30, height: 30)
                    .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
                    .offset(
                        x: CGFloat(index) * 12 - CGFloat(min(2, group.participants.count - 1)) * 6,
                        y: 0,
                    )
                }
            }
        } else {
            ProfileImageView(
                photo: group.user.profilePhoto?.small,
                minithumbnail: group.user.profilePhoto?.minithumbnail,
                title: group.title,
                userId: group.user.id,
            )
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
            groups = await resolve(found.messages)
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
            let existingIds = Set(groups.map(\.id))
            groups.append(contentsOf: loaded.filter { !existingIds.contains($0.id) })
            nextOffset = found.nextOffset
        } catch is CancellationError {
            return
        } catch {
            errorMessage = telegramErrorDescription(error)
        }
    }

    /// Classifies each message, coalesces consecutive runs with the same peer, then resolves the
    /// peer (and, for a conference, a few participant avatars) once per run.
    private func resolve(_ messages: [Message]) async -> [CallHistoryGroup] {
        let entries = messages.compactMap(TelegramCallHistoryEntry.init(message:))
        var runs = [[TelegramCallHistoryEntry]]()
        for entry in entries {
            if var last = runs.last, last.first?.chatId == entry.chatId {
                last.append(entry)
                runs[runs.count - 1] = last
            } else {
                runs.append([entry])
            }
        }

        return await runs.concurrentCompactMap { run in
            guard let chatId = run.first?.chatId,
                  let chat = try? await service.getChat(chatId: chatId)
            else { return nil }
            let userId: Int64
            switch chat.type {
            case .chatTypePrivate(let value): userId = value.userId
            case .chatTypeSecret(let value): userId = value.userId
            case .chatTypeBasicGroup, .chatTypeSupergroup: return nil
            }
            guard let user = try? await service.getUser(userId: userId) else { return nil }

            var participants = [CallHistoryParticipant]()
            if run.first?.isConference == true {
                participants = await (run.first?.otherParticipantIds ?? [])
                    .prefix(3)
                    .concurrentCompactMap { await resolveParticipant($0) }
            }
            return CallHistoryGroup(entries: run, chat: chat, user: user, participants: participants)
        }
    }

    private func resolveParticipant(_ sender: MessageSender) async -> CallHistoryParticipant? {
        switch sender {
        case .messageSenderUser(let value):
            guard let user = try? await service.getUser(userId: value.userId) else { return nil }
            return CallHistoryParticipant(
                id: user.id,
                title: telegramUserDisplayName(user),
                photo: user.profilePhoto?.small,
                minithumbnail: user.profilePhoto?.minithumbnail,
            )
        case .messageSenderChat(let value):
            guard let chat = try? await service.getChat(chatId: value.chatId) else { return nil }
            return CallHistoryParticipant(
                id: value.chatId,
                title: chat.title,
                photo: chat.photo?.small,
                minithumbnail: chat.photo?.minithumbnail,
            )
        }
    }

    private func activate(_ group: CallHistoryGroup, videoOverride: Bool? = nil) {
        if group.isConference {
            Task { @MainActor in
                if session.groupCallCoordinator != nil {
                    session.restoreCallView()
                } else {
                    let joined = await session.joinConference(
                        chatId: group.top.chatId,
                        messageId: group.top.id,
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
            userId: group.user.id,
            displayName: group.title,
            isVideo: videoOverride ?? group.isVideo,
            onMicrophonePermissionDenied: {
                errorMessage = "Microphone access is required to make calls."
            },
            onCameraPermissionDenied: {
                errorMessage = "Camera access is required to start video calls."
            },
        )
    }

    @MainActor private func openChat(_ group: CallHistoryGroup) async {
        pushedChat = await rootVM.getCustomChat(from: group.chat.id)
        if pushedChat == nil {
            errorMessage = "The conversation couldn't be opened."
        }
    }

    private func delete(_ group: CallHistoryGroup) {
        groups.removeAll { $0.id == group.id }
        let chatId = group.top.chatId
        let messageIds = group.entries.map(\.id)
        Task {
            do {
                _ = try await service.deleteMessages(
                    chatId: chatId,
                    messageIds: messageIds,
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
            groups = []
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
