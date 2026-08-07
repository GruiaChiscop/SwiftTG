// ChatInfoView.swift

import SwiftUI
import TDLibKit

// MARK: - ChatInfoView

struct ChatInfoView: View {
    // MARK: Internal

    var body: some View {
        List {
            identitySection(info)

            if let info {
                profileInformationSection(info)
                notificationsSection(info)
                memberDetailsSection(info)
                sharedContentSection(info)
                unofficialAppWarningSection(info)
                actionsSection(info)
            } else if isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView("Loading chat information…")
                        Spacer()
                    }
                }
            } else {
                Section {
                    ContentUnavailableView(
                        "Chat Information Unavailable",
                        systemImage: "exclamationmark.triangle",
                        description: Text("Telegram didn't return information for this chat."),
                    )
                }
            }
        }
        .navigationTitle("Chat Info")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: ChatInfoDestination.self) { destination in
            destinationView(destination)
        }
        .task(id: chat.id) { await loadInfo() }
        .sheet(isPresented: $showsSharedMedia) {
            SharedMediaView(
                chatId: chat.id,
                chatTitle: chat.displayTitle,
                service: chatVM.service,
            ) { messageId in
                openSharedMediaMessage(messageId)
            }
        }
        .sheet(isPresented: $showsScheduledMessages) {
            ScheduledMessagesView()
        }
        .popover(isPresented: $showMuteOptions) {
            TelegramMutePresetPopoverContent { duration in
                setMuteDuration(duration)
                showMuteOptions = false
            }
            .presentationCompactAdaptation(.popover)
        }
        .alert(
            "Delete \(chat.displayTitle)?",
            isPresented: $showDeleteConfirmation,
        ) {
            if chat.actionPolicy.canDeleteCommunity {
                Button("Delete for everyone", role: .destructive) {
                    deleteChat(forAll: true)
                }
            } else {
                if chat.chat.canBeDeletedOnlyForSelf {
                    Button("Delete only for me", role: .destructive) {
                        deleteChat(forAll: false)
                    }
                }
                if chat.chat.canBeDeletedForAllUsers {
                    Button("Delete for everyone", role: .destructive) {
                        deleteChat(forAll: true)
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                showDeleteConfirmation = false
            }
        }
        .alert(
            "Chat Info Error",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: {
                    if !$0 {
                        errorMessage = nil
                    }
                },
            ),
        ) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Private

    @Environment(ChatVM.self) private var chatVM
    @Environment(\.dismiss) private var dismiss

    @State private var errorMessage: String?
    @State private var info: TelegramChatInfoData?
    @State private var isLoading = true
    @State private var muteOverride: Bool?
    @State private var showDeleteConfirmation = false
    @State private var showMuteOptions = false
    @State private var showsScheduledMessages = false
    @State private var showsSharedMedia = false

    private var chat: CustomChat { chatVM.customChat }

    private var status: String {
        !chatVM.actionStatus.isEmpty ? chatVM.actionStatus : chatVM.onlineStatus
    }

    private func identitySection(_ info: TelegramChatInfoData?) -> some View {
        Section {
            VStack(spacing: 12) {
                VStack(spacing: 12) {
                    ProfileImageView(
                        photo: chat.chat.photo?.big,
                        minithumbnail: chat.chat.photo?.minithumbnail,
                        title: chat.displayTitle,
                        userId: chat.chat.id,
                        fontSize: 36,
                        isSavedMessages: chat.isSavedMessages,
                    )
                    .frame(width: 96, height: 96)

                    Text(chat.displayTitle)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)

                    let identityStatus = status.isEmpty ? chat.kind.title : status
                    Text(identityStatus)
                        .font(.subheadline)
                        .foregroundStyle(identityStatus == "online" ? .blue : .secondary)
                }
                .accessibilityElement(children: .combine)

                Button {
                    openConversationSearch()
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "magnifyingglass")
                        Text("Search")
                            .font(.caption)
                    }
                    .frame(minWidth: 88, minHeight: 44)
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func notificationsSection(_ info: TelegramChatInfoData) -> some View {
        Section("Notifications") {
            Button {
                if isMuted(info) {
                    setMuteDuration(0)
                } else {
                    showMuteOptions = true
                }
            } label: {
                Text(isMuted(info) ? "Unmute" : "Mute")
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            TelegramChatSoundRow(service: chatVM.service, chatId: chat.id, settings: chat.notificationSettings)
        }
    }

    private func sharedContentSection(_ info: TelegramChatInfoData) -> some View {
        Section {
            Button {
                showsSharedMedia = true
            } label: {
                Label("Shared Media", systemImage: "photo.on.rectangle")
            }

            Button {
                showsScheduledMessages = true
            } label: {
                Label("Scheduled Messages", systemImage: "clock")
            }

            if let commonGroupCount = info.commonGroupCount,
               commonGroupCount > 0,
               let userId = info.commonGroupsUserId
            {
                NavigationLink(value: ChatInfoDestination.commonGroups(userId: userId, count: commonGroupCount)) {
                    LabeledContent("Groups in common", value: commonGroupCount.formatted())
                }
            }
        }
    }

    @ViewBuilder private func profileInformationSection(_ info: TelegramChatInfoData) -> some View {
        if !info.usernames.isEmpty || info.phoneNumber != nil || info.birthdate != nil || info.about != nil {
            Section {
                if let phoneNumber = info.phoneNumber {
                    LabeledContent("Phone", value: phoneNumber)
                        .textSelection(.enabled)
                }

                if let username = info.usernames.first,
                   let url = URL(string: "https://t.me/\(username)")
                {
                    profileLinkRow(username: username, usernames: info.usernames, url: url)
                }

                if let birthdate = info.birthdate {
                    LabeledContent("Birthdate", value: birthdate)
                }

                if let about = info.about, !about.text.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(profileInformationLabel(info))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(getAttributedString(from: about, .primary))
                    }
                    .textSelection(.enabled)
                }
            }
        }
    }

    @ViewBuilder private func memberDetailsSection(_ info: TelegramChatInfoData) -> some View {
        if info.memberCount != nil
            || info.administratorCount != nil
            || info.restrictedCount != nil
            || info.bannedCount != nil
        {
            Section {
                if let memberCount = info.memberCount {
                    let title = chat.kind == .channel ? "Subscribers" : "Members"
                    if info.canBrowseMembers {
                        NavigationLink(value: ChatInfoDestination.members(.members)) {
                            LabeledContent(title, value: memberCount.formatted())
                        }
                    } else {
                        LabeledContent(title, value: memberCount.formatted())
                    }
                }

                if let administratorCount = info.administratorCount, administratorCount > 0 {
                    NavigationLink(value: ChatInfoDestination.members(.administrators)) {
                        LabeledContent("Administrators", value: administratorCount.formatted())
                    }
                }

                if let restrictedCount = info.restrictedCount, restrictedCount > 0 {
                    NavigationLink(value: ChatInfoDestination.members(.restricted)) {
                        LabeledContent("Restricted", value: restrictedCount.formatted())
                    }
                }

                if let bannedCount = info.bannedCount, bannedCount > 0 {
                    NavigationLink(value: ChatInfoDestination.members(.banned)) {
                        LabeledContent("Banned", value: bannedCount.formatted())
                    }
                }
            }
        }
    }

    @ViewBuilder private func unofficialAppWarningSection(_ info: TelegramChatInfoData) -> some View {
        if info.usesUnofficialApp {
            Section {
                Label(
                    "Telegram reports that this user uses an unofficial app that may pose a security risk.",
                    systemImage: "exclamationmark.triangle",
                )
                .foregroundStyle(.orange)
            }
        }
    }

    private func profileLinkRow(
        username: String,
        usernames: [String],
        url: URL,
    ) -> some View {
        let isPublicChat = chat.kind == .group || chat.kind == .channel
        let title = isPublicChat ? url.absoluteString : "@\(username)"
        let subtitle = profileLinkSubtitle(usernames, isPublicChat: isPublicChat)
        let copyValue = isPublicChat ? url.absoluteString : "@\(username)"

        return Link(destination: url) {
            HStack(spacing: 12) {
                Image(systemName: isPublicChat ? "link" : "at")
                    .frame(width: 20)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.forward")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .contextMenu {
            if copyValue != url.absoluteString {
                Button("Copy") { UIPasteboard.general.string = copyValue }
            }
            Button("Copy Link") { UIPasteboard.general.string = url.absoluteString }
        }
    }

    @ViewBuilder private func destinationView(_ destination: ChatInfoDestination) -> some View {
        switch destination {
        case .members(let filter):
            ChatInfoMembersView(
                chatId: chat.id,
                isChannel: chat.kind == .channel,
                filter: filter,
                service: chatVM.service,
                onSelect: openMember,
            )
        case .commonGroups(let userId, let count):
            ChatInfoCommonGroupsView(
                userId: userId,
                expectedCount: count,
                service: chatVM.service,
                onSelect: openChat,
            )
        }
    }

    @ViewBuilder private func actionsSection(_ info: TelegramChatInfoData) -> some View {
        let policy = chat.actionPolicy
        if info.blockableUserId != nil
            || policy.canLeave
            || policy.canClearHistory
            || policy.canDeleteChat
        {
            Section {
                if info.blockableUserId != nil {
                    Button(
                        blockActionTitle(info),
                        role: info.isBlocked ? nil : .destructive,
                    ) {
                        toggleBlocked()
                    }
                }

                if let leaveTitle = policy.leaveActionTitle {
                    Button(leaveTitle, role: .destructive) {
                        dismissThenRequest { RootVM.shared.requestLeave(chat) }
                    }
                }

                if policy.canClearHistory {
                    Button("Clear History", role: .destructive) {
                        dismissThenRequest { RootVM.shared.requestClearHistory(chat) }
                    }
                }

                if policy.canDeleteChat, policy.leaveActionTitle == nil {
                    Button(policy.deleteActionTitle, role: .destructive) {
                        showDeleteConfirmation = true
                    }
                }
            }
        }
    }

    private func isMuted(_ info: TelegramChatInfoData) -> Bool {
        if let muteOverride {
            return muteOverride
        }
        let settings = chat.notificationSettings
        return settings.useDefaultMuteFor ? info.defaultMuteFor > 0 : settings.muteFor > 0
    }

    private func setMuteDuration(_ duration: Int) {
        muteOverride = duration > 0
        RootVM.shared.setMuteDuration(duration, for: chat)
    }

    private func deleteChat(forAll: Bool) {
        RootVM.shared.deleteChat(chat, forAll: forAll)
        dismiss()
    }

    private func openSharedMediaMessage(_ messageId: Int64) {
        showsSharedMedia = false
        Task { @MainActor in
            await Task.yield()
            dismiss()
            await Task.yield()
            chatVM.navigateToMessage(id: messageId)
        }
    }

    private func openConversationSearch() {
        dismiss()
        Task { @MainActor in
            await Task.yield()
            chatVM.beginConversationSearch()
        }
    }

    private func blockActionTitle(_ info: TelegramChatInfoData) -> String {
        if info.isBot {
            return info.isBlocked ? "Restart Bot" : "Stop Bot"
        }
        return info.isBlocked ? "Unblock User" : "Block User"
    }

    private func profileInformationLabel(_ info: TelegramChatInfoData) -> String {
        if info.isBot {
            return "Bot Info"
        }
        return chat.kind == .group || chat.kind == .channel ? "Description" : "Bio"
    }

    private func toggleBlocked() {
        guard let current = info, let userId = current.blockableUserId else { return }
        Task {
            do {
                let blocked = !current.isBlocked
                _ = try await chatVM.service.setMessageSenderBlockList(
                    blockList: blocked ? .blockListMain : nil,
                    senderId: .messageSenderUser(.init(userId: userId)),
                )
                guard !Task.isCancelled else { return }
                info?.isBlocked = blocked
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func profileLinkSubtitle(_ usernames: [String], isPublicChat: Bool) -> String {
        let label = isPublicChat ? "Link" : "Username"
        guard usernames.count > 1 else { return label }
        return "\(label). Also: \(usernames.dropFirst().map { "@\($0)" }.joined(separator: ", "))"
    }

    private func dismissThenRequest(_ request: @escaping @MainActor () -> Void) {
        dismiss()
        Task { @MainActor in
            await Task.yield()
            request()
        }
    }

    private func loadInfo() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let loaded = try await TelegramChatInfoLoader(service: chatVM.service).load(chatId: chat.id)
            guard !Task.isCancelled else { return }
            info = loaded
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
            info = nil
        }
    }

    private func openMember(_ sender: MessageSender) {
        Task {
            let customChat: CustomChat? =
                switch sender {
                case .messageSenderUser(let value):
                    await RootVM.shared.getPrivateCustomChat(userId: value.userId)
                case .messageSenderChat(let value):
                    await RootVM.shared.getCustomChat(from: value.chatId)
                }
            await openResolvedChat(customChat)
        }
    }

    private func openChat(_ resolvedChat: Chat) {
        Task {
            let customChat = await RootVM.shared.getCustomChat(from: resolvedChat.id)
            await openResolvedChat(customChat)
        }
    }

    @MainActor private func openResolvedChat(_ customChat: CustomChat?) async {
        guard let customChat else {
            errorMessage = "This chat is private or unavailable."
            return
        }
        dismiss()
        await Task.yield()
        RootVM.shared.navigate(to: .customChat(customChat, messageId: nil))
    }
}
