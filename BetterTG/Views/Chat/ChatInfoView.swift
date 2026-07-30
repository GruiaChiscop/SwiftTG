// ChatInfoView.swift

import SwiftUI
import TDLibKit

// MARK: - ChatInfoData

private struct ChatInfoData {
    var about: FormattedText?
    var usernames = [String]()
    var phoneNumber: String?
    var birthdate: String?
    var memberCount: Int?
    var administratorCount: Int?
    var restrictedCount: Int?
    var bannedCount: Int?
    var commonGroupCount: Int?
    var commonGroupsUserId: Int64?
    var isBlocked = false
    var defaultMuteFor = 0
    var usesUnofficialApp = false
    var isBot = false
    var blockableUserId: Int64?
    var canBrowseMembers = false
}

// MARK: - ChatInfoView

struct ChatInfoView: View {
    // MARK: Internal

    var body: some View {
        List {
            identitySection(info)

            if let info {
                profileInformationSection(info)
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
                chatTitle: chat.chat.title,
                service: chatVM.service,
            ) { messageId in
                openSharedMediaMessage(messageId)
            }
        }
        .confirmationDialog("Mute \(chat.chat.title)", isPresented: $showMuteOptions) {
            ForEach(TelegramMutePreset.allCases) { preset in
                Button(preset.title) { setMuteDuration(preset.duration) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert(
            "Delete \(chat.chat.title)?",
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
    @State private var info: ChatInfoData?
    @State private var isLoading = true
    @State private var muteOverride: Bool?
    @State private var showDeleteConfirmation = false
    @State private var showMuteOptions = false
    @State private var showsSharedMedia = false

    private var chat: CustomChat { chatVM.customChat }

    private var status: String {
        !chatVM.actionStatus.isEmpty ? chatVM.actionStatus : chatVM.onlineStatus
    }

    private func identitySection(_ info: ChatInfoData?) -> some View {
        Section {
            VStack(spacing: 12) {
                VStack(spacing: 12) {
                    ProfileImageView(
                        photo: chat.chat.photo?.big,
                        minithumbnail: chat.chat.photo?.minithumbnail,
                        title: chat.chat.title,
                        userId: chat.chat.id,
                        fontSize: 36,
                    )
                    .frame(width: 96, height: 96)

                    Text(chat.chat.title)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)

                    let identityStatus = status.isEmpty ? chat.kind.title : status
                    Text(identityStatus)
                        .font(.subheadline)
                        .foregroundStyle(identityStatus == "online" ? .blue : .secondary)
                }
                .accessibilityElement(children: .combine)

                if let info {
                    HStack(spacing: 12) {
                        Button {
                            if isMuted(info) {
                                setMuteDuration(0)
                            } else {
                                showMuteOptions = true
                            }
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: isMuted(info) ? "bell.slash.fill" : "bell.fill")
                                Text(isMuted(info) ? "Unmute" : "Mute")
                                    .font(.caption)
                            }
                            .frame(minWidth: 88, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel(isMuted(info) ? "Unmute notifications" : "Mute notifications")

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
                        .accessibilityLabel("Search in conversation")
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func sharedContentSection(_ info: ChatInfoData) -> some View {
        Section {
            Button {
                showsSharedMedia = true
            } label: {
                Label("Shared Media", systemImage: "photo.on.rectangle")
            }
            .accessibilityHint("Shows media, files, links, music, and voice messages")

            if let commonGroupCount = info.commonGroupCount,
               commonGroupCount > 0,
               let userId = info.commonGroupsUserId
            {
                NavigationLink(value: ChatInfoDestination.commonGroups(userId: userId, count: commonGroupCount)) {
                    LabeledContent("Groups in common", value: commonGroupCount.formatted())
                }
                .accessibilityHint("Opens the groups in common")
            }
        }
    }

    @ViewBuilder private func profileInformationSection(_ info: ChatInfoData) -> some View {
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

    @ViewBuilder private func memberDetailsSection(_ info: ChatInfoData) -> some View {
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
                        .accessibilityHint("Opens the \(title.lowercased()) list")
                    } else {
                        LabeledContent(title, value: memberCount.formatted())
                    }
                }

                if let administratorCount = info.administratorCount, administratorCount > 0 {
                    NavigationLink(value: ChatInfoDestination.members(.administrators)) {
                        LabeledContent("Administrators", value: administratorCount.formatted())
                    }
                    .accessibilityHint("Opens the administrators list")
                }

                if let restrictedCount = info.restrictedCount, restrictedCount > 0 {
                    NavigationLink(value: ChatInfoDestination.members(.restricted)) {
                        LabeledContent("Restricted", value: restrictedCount.formatted())
                    }
                    .accessibilityHint("Opens the restricted members list")
                }

                if let bannedCount = info.bannedCount, bannedCount > 0 {
                    NavigationLink(value: ChatInfoDestination.members(.banned)) {
                        LabeledContent("Banned", value: bannedCount.formatted())
                    }
                    .accessibilityHint("Opens the banned members list")
                }
            }
        }
    }

    @ViewBuilder private func unofficialAppWarningSection(_ info: ChatInfoData) -> some View {
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
        .accessibilityLabel(isPublicChat ? "Link: \(url.absoluteString)" : "Username: \(username)")
        .accessibilityHint("Opens the link")
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

    @ViewBuilder private func actionsSection(_ info: ChatInfoData) -> some View {
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

    private func isMuted(_ info: ChatInfoData) -> Bool {
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

    private func blockActionTitle(_ info: ChatInfoData) -> String {
        if info.isBot {
            return info.isBlocked ? "Restart Bot" : "Stop Bot"
        }
        return info.isBlocked ? "Unblock User" : "Block User"
    }

    private func profileInformationLabel(_ info: ChatInfoData) -> String {
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
            let resolvedChat = try await chatVM.service.getChat(chatId: chat.id)
            var loaded = ChatInfoData()
            let scopeSettings = try? await chatVM.service.getScopeNotificationSettings(
                scope: notificationScope(for: resolvedChat.type),
            )
            loaded.defaultMuteFor = scopeSettings?.muteFor ?? 0

            switch resolvedChat.type {
            case .chatTypePrivate(let value):
                await populateUserInfo(&loaded, userId: value.userId)
            case .chatTypeSecret(let value):
                await populateUserInfo(&loaded, userId: value.userId)
            case .chatTypeBasicGroup(let value):
                await populateBasicGroupInfo(&loaded, groupId: value.basicGroupId)
            case .chatTypeSupergroup(let value):
                await populateSupergroupInfo(&loaded, groupId: value.supergroupId)
            }

            guard !Task.isCancelled else { return }
            info = loaded
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
            info = nil
        }
    }

    private func populateUserInfo(_ info: inout ChatInfoData, userId: Int64) async {
        guard let user = try? await chatVM.service.getUser(userId: userId) else { return }
        info.usernames = user.usernames?.activeUsernames ?? []
        info.phoneNumber = user.phoneNumber.isEmpty ? nil : "+\(user.phoneNumber)"

        let currentUserId = await (try? chatVM.service.getMe())?.id
        switch user.type {
        case .userTypeBot:
            info.isBot = true
            info.blockableUserId = userId == currentUserId ? nil : userId
        case .userTypeRegular:
            info.blockableUserId = userId == currentUserId ? nil : userId
        case .userTypeDeleted, .userTypeUnknown:
            break
        }

        guard let full = try? await chatVM.service.getUserFullInfo(userId: userId) else { return }
        if let shortDescription = full.botInfo?.shortDescription.nilIfEmpty {
            info.about = FormattedText(entities: [], text: shortDescription)
        } else if let bio = full.bio, !bio.text.isEmpty {
            info.about = bio
        }
        info.birthdate = full.birthdate.map(chatInfoBirthdateDescription)
        info.commonGroupCount = full.groupInCommonCount
        info.commonGroupsUserId = full.groupInCommonCount > 0 ? userId : nil
        info.isBlocked = full.blockList == .blockListMain
        info.usesUnofficialApp = full.usesUnofficialApp
    }

    private func populateBasicGroupInfo(_ info: inout ChatInfoData, groupId: Int64) async {
        guard let group = try? await chatVM.service.getBasicGroup(basicGroupId: groupId) else { return }
        info.memberCount = group.memberCount
        info.canBrowseMembers = true

        guard let full = try? await chatVM.service.getBasicGroupFullInfo(basicGroupId: groupId) else { return }
        info.about = full.description.nilIfEmpty.map { FormattedText(entities: [], text: $0) }
        info.memberCount = max(group.memberCount, full.members.count)
        if chatInfoCanManageMembers(group.status) {
            info.administratorCount = full.members.filter { chatInfoIsAdministrator($0.status) }.count
        }
        if chatInfoCanRestrictMembers(group.status) {
            info.restrictedCount = full.members
                .filter {
                    if case .chatMemberStatusRestricted = $0.status {
                        true
                    } else {
                        false
                    }
                }
                .count
            info.bannedCount = full.members
                .filter {
                    if case .chatMemberStatusBanned = $0.status {
                        true
                    } else {
                        false
                    }
                }
                .count
        }
    }

    private func populateSupergroupInfo(_ info: inout ChatInfoData, groupId: Int64) async {
        guard let group = try? await chatVM.service.getSupergroup(supergroupId: groupId) else { return }
        info.usernames = group.usernames?.activeUsernames ?? []
        info.memberCount = group.memberCount > 0 ? group.memberCount : nil

        guard let full = try? await chatVM.service.getSupergroupFullInfo(supergroupId: groupId) else { return }
        info.about = full.description.nilIfEmpty.map { FormattedText(entities: [], text: $0) }
        info.memberCount = max(group.memberCount, full.memberCount)
        info.canBrowseMembers = full.canGetMembers
        if chatInfoCanManageMembers(group.status) {
            info.administratorCount = full.administratorCount
        }
        if chatInfoCanRestrictMembers(group.status) {
            info.restrictedCount = full.restrictedCount
            info.bannedCount = full.bannedCount
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

private func notificationScope(for type: ChatType) -> NotificationSettingsScope {
    switch type {
    case .chatTypePrivate, .chatTypeSecret:
        .notificationSettingsScopePrivateChats
    case .chatTypeBasicGroup:
        .notificationSettingsScopeGroupChats
    case .chatTypeSupergroup(let value):
        value.isChannel ? .notificationSettingsScopeChannelChats : .notificationSettingsScopeGroupChats
    }
}

private func chatInfoCanManageMembers(_ status: ChatMemberStatus) -> Bool {
    switch status {
    case .chatMemberStatusAdministrator, .chatMemberStatusCreator:
        true
    case .chatMemberStatusBanned, .chatMemberStatusLeft, .chatMemberStatusMember,
         .chatMemberStatusRestricted:
        false
    }
}

private func chatInfoCanRestrictMembers(_ status: ChatMemberStatus) -> Bool {
    switch status {
    case .chatMemberStatusCreator:
        true
    case .chatMemberStatusAdministrator(let value):
        value.rights.canRestrictMembers
    case .chatMemberStatusBanned, .chatMemberStatusLeft, .chatMemberStatusMember,
         .chatMemberStatusRestricted:
        false
    }
}

private func chatInfoIsAdministrator(_ status: ChatMemberStatus) -> Bool {
    switch status {
    case .chatMemberStatusAdministrator, .chatMemberStatusCreator:
        true
    case .chatMemberStatusBanned, .chatMemberStatusLeft, .chatMemberStatusMember,
         .chatMemberStatusRestricted:
        false
    }
}

private func chatInfoBirthdateDescription(_ birthdate: Birthdate) -> String {
    let calendar = Calendar.autoupdatingCurrent
    let now = Date()
    var components = DateComponents()
    components.calendar = calendar
    components.day = birthdate.day
    components.month = birthdate.month
    components.year = birthdate.year == 0 ? 2000 : birthdate.year
    guard let date = components.date else { return "\(birthdate.day)/\(birthdate.month)" }

    var description = date.formatted(
        Date.FormatStyle()
            .month(.wide)
            .day()
            .year(birthdate.year == 0 ? .omitted : .defaultDigits),
    )
    if birthdate.year > 0 {
        let age = calendar.dateComponents([.year], from: date, to: now).year ?? 0
        if age >= 0 {
            description += ", \(age) years old"
        }
    }
    let today = calendar.dateComponents([.day, .month], from: now)
    if today.day == birthdate.day, today.month == birthdate.month {
        description += ", birthday today"
    }
    return description
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
