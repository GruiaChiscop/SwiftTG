// MacChatInfo.swift

import AppKit
import SwiftUI
import TDLibKit

// MARK: - MacChatInfoView

struct MacChatInfoView: View {
    // MARK: Internal

    @Bindable var model: MacSessionModel

    let chat: ChatListItemState

    var body: some View {
        NavigationStack {
            Group {
                if let info {
                    List {
                        identitySection(info)
                        notificationsSection()
                        autoDeleteSection(info)
                        detailsSections(info)
                        sharedMediaSection(info)
                        unofficialAppWarningSection(info)
                        membersSection(info)
                        actionsSection(info)
                    }
                    .listStyle(.inset)
                } else if isLoading {
                    ProgressView("Loading chat information…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView(
                        "Chat Information Unavailable",
                        systemImage: "exclamationmark.triangle",
                        description: Text("Telegram didn't return information for this chat."),
                    )
                }
            }
            .navigationTitle("Chat Info")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 520, idealWidth: 620, minHeight: 560, idealHeight: 720)
        .task(id: chat.chatId) { await loadInfo() }
        .sheet(item: $memberListFilter) { filter in
            MacChatMembersView(model: model, chat: chat, filter: filter) { senderId in
                memberListFilter = nil
                dismiss()
                model.activateChatInfoMember(senderId)
            }
        }
        .sheet(isPresented: $showsCommonGroups) {
            if let userId = info?.commonGroupsUserId {
                MacCommonGroupsView(model: model, userId: userId, expectedCount: info?.commonGroupCount ?? 0) { chat in
                    showsCommonGroups = false
                    dismiss()
                    model.activateChatInfoChat(chat)
                }
            }
        }
        .sheet(isPresented: $showsSharedMedia) {
            MacSharedMediaView(model: model, chat: currentChat) { messageId in
                showsSharedMedia = false
                Task { @MainActor in
                    await Task.yield()
                    dismiss()
                    model.activateChat(chat.chatId, messageId: messageId)
                }
            }
        }
        .sheet(item: $reportRequest) { request in
            TelegramReportView(service: model.service, request: request)
                .frame(minWidth: 380, minHeight: 320)
        }
        .sheet(isPresented: $showsAddContact) {
            if let info, let userId = info.privateChatUserId {
                AddContactSheet(
                    userId: userId,
                    firstName: info.contactFirstName,
                    lastName: info.contactLastName,
                    phoneNumber: info.phoneNumber,
                    service: model.service,
                ) {
                    self.info?.isContact = true
                }
            }
        }
        .sheet(isPresented: $showsScheduledMessages) {
            MacScheduledMessagesView(model: model)
        }
        .popover(isPresented: $showMuteOptions) {
            TelegramMutePresetPopoverContent { duration in
                model.setMuteDuration(duration, for: currentChat)
                showMuteOptions = false
            }
        }
        .alert("Leave \(chat.title)?", isPresented: $confirmLeave) {
            Button("Leave", role: .destructive) {
                Task {
                    if await model.leaveChatFromInfo(currentChat) {
                        dismiss()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You will leave this chat and may lose access to its messages.")
        }
        .alert("Start Secret Chat", isPresented: $confirmStartSecretChat) {
            Button("Start") {
                if let userId = info?.privateChatUserId {
                    dismiss()
                    model.startSecretChat(userId: userId)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Start a secret chat with \(chat.displayTitle)?")
        }
        .alert(blockDialogTitle, isPresented: $confirmBlock) {
            Button(blockConfirmationTitle, role: info?.isBlocked == true ? nil : .destructive) {
                toggleBlock()
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert(deleteDialogTitle, isPresented: $showDeleteOptions) {
            if chat.kind == .privateChat || chat.kind == .secretChat,
               currentChat.canBeDeletedOnlyForSelf
            {
                Button("Delete only for me", role: .destructive) {
                    model.deleteChat(currentChat, forEveryone: false)
                    dismiss()
                }
            }
            if chat.kind == .privateChat || chat.kind == .secretChat,
               currentChat.canBeDeletedForAllUsers
            {
                Button("Delete for everyone", role: .destructive) {
                    model.deleteChat(currentChat, forEveryone: true)
                    dismiss()
                }
            }
            if chat.kind == .group || chat.kind == .channel {
                Button("Delete for everyone", role: .destructive) {
                    Task {
                        if await model.deleteCommunityFromInfo(currentChat) {
                            dismiss()
                        }
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Clear history in \(chat.displayTitle)?", isPresented: $showClearHistoryOptions) {
            if currentChat.canBeDeletedOnlyForSelf {
                Button("Clear only for me", role: .destructive) {
                    model.clearChatHistory(currentChat, forEveryone: false)
                }
            }
            if currentChat.canBeDeletedForAllUsers {
                Button("Clear for everyone", role: .destructive) {
                    model.clearChatHistory(currentChat, forEveryone: true)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All messages will be removed, but the chat will remain in your chat list.")
        }
        .alert(
            "Chat Info Error",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { isPresented in
                    if !isPresented {
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

    /// Telegram-iOS's `PeerAutoremoveSetupScreen` preset stops: Off, 1 day, 1 week, 31 days.
    private static let autoDeletePresets: [(title: String, seconds: Int)] = [
        ("Off", 0),
        ("1 Day", 86400),
        ("1 Week", 604_800),
        ("1 Month", 2_678_400),
    ]

    @Environment(\.dismiss) private var dismiss
    @State private var avatarPath: String?
    @State private var confirmBlock = false
    @State private var confirmLeave = false
    @State private var confirmStartSecretChat = false
    @State private var showsAddContact = false
    @State private var info: TelegramChatInfoData?
    @State private var isLoading = true
    @State private var reportRequest: TelegramReportRequest?
    @State private var memberListFilter: TelegramChatInfoMemberFilter?
    @State private var showClearHistoryOptions = false
    @State private var showDeleteOptions = false
    @State private var showMuteOptions = false
    @State private var autoDeleteOverride: Int?
    @State private var isSavingAutoDelete = false
    @State private var errorMessage: String?
    @State private var showsCommonGroups = false
    @State private var showsScheduledMessages = false
    @State private var showsSharedMedia = false

    private var currentChat: ChatListItemState {
        model.chatList.items[chat.chatId] ?? chat
    }

    private var autoDeleteSeconds: Int {
        autoDeleteOverride ?? info?.messageAutoDeleteTime ?? 0
    }

    private var autoDeleteDescription: String {
        Self.autoDeleteLabel(autoDeleteSeconds)
    }

    private var isMuted: Bool {
        guard let settings = currentChat.notificationSettings else {
            return (info?.defaultMuteFor ?? 0) > 0
        }
        return settings.useDefaultMuteFor
            ? (info?.defaultMuteFor ?? 0) > 0
            : settings.muteFor > 0
    }

    private var chatNotificationSettings: ChatNotificationSettings {
        currentChat.notificationSettings ?? ChatNotificationSettings(
            disableMentionNotifications: false,
            disablePinnedMessageNotifications: false,
            muteFor: 0,
            muteStories: false,
            showPreview: true,
            showStoryPoster: true,
            soundId: 0,
            storySoundId: 0,
            useDefaultDisableMentionNotifications: true,
            useDefaultDisablePinnedMessageNotifications: true,
            useDefaultMuteFor: true,
            useDefaultMuteStories: true,
            useDefaultShowPreview: true,
            useDefaultShowStoryPoster: true,
            useDefaultSound: true,
            useDefaultStorySound: true,
        )
    }

    private var blockDialogTitle: String {
        if info?.isBot == true {
            return info?.isBlocked == true ? "Restart \(chat.title)?" : "Stop \(chat.title)?"
        }
        return info?.isBlocked == true ? "Unblock \(chat.title)?" : "Block \(chat.title)?"
    }

    private var blockConfirmationTitle: String {
        if info?.isBot == true {
            return info?.isBlocked == true ? "Restart" : "Stop"
        }
        return info?.isBlocked == true ? "Unblock" : "Block"
    }

    private var deleteDialogTitle: String {
        "\(currentChat.actionPolicy.deleteActionTitle) \(chat.displayTitle)?"
    }

    /// TDLib's `Chat.canBeReported` isn't carried on `ChatListItemState`, so approximate it: every
    /// chat can be reported except your own Saved Messages and E2E secret chats. `reportChat` still
    /// rejects anything the server won't accept, which the report sheet surfaces as a failure.
    private var canReportChat: Bool {
        !currentChat.isSavedMessages && chat.kind != .secretChat
    }

    private var autoDeleteRowLabel: some View {
        LabeledContent {
            Text(autoDeleteDescription)
        } label: {
            Label("Auto-Delete Messages", systemImage: "timer")
        }
        .contentShape(Rectangle())
    }

    private func notificationsSection() -> some View {
        Section("Notifications") {
            Button {
                if isMuted {
                    model.setMuteDuration(0, for: currentChat)
                } else {
                    showMuteOptions = true
                }
            } label: {
                Text(isMuted ? "Unmute" : "Mute")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            TelegramChatSoundRow(service: model.service, chatId: chat.chatId, settings: chatNotificationSettings)

            TelegramChatNotificationTogglesRow(
                service: model.service,
                chatId: chat.chatId,
                settings: chatNotificationSettings,
                defaultShowPreview: info?.defaultShowPreview ?? true,
                defaultMuteStories: info?.defaultMuteStories ?? false,
                onError: { errorMessage = $0 },
            )
        }
    }

    @ViewBuilder private func autoDeleteSection(_ info: TelegramChatInfoData) -> some View {
        let canEdit = canEditAutoDelete(info)
        if canEdit || autoDeleteSeconds > 0 {
            Section {
                if canEdit {
                    Menu {
                        ForEach(Self.autoDeletePresets, id: \.seconds) { preset in
                            Button {
                                setAutoDelete(preset.seconds)
                            } label: {
                                if autoDeleteSeconds == preset.seconds {
                                    Label(preset.title, systemImage: "checkmark")
                                } else {
                                    Text(preset.title)
                                }
                            }
                        }
                    } label: {
                        autoDeleteRowLabel
                    }
                    .disabled(isSavingAutoDelete)
                } else {
                    autoDeleteRowLabel
                }
            } footer: {
                Text("Automatically delete messages sent in this chat after a certain period of time.")
            }
        }
    }

    private func sharedMediaSection(_ info: TelegramChatInfoData) -> some View {
        Section {
            Button("Shared Media", systemImage: "photo.on.rectangle") {
                showsSharedMedia = true
            }

            Button("Scheduled Messages", systemImage: "clock") {
                showsScheduledMessages = true
            }

            if let commonGroupCount = info.commonGroupCount, commonGroupCount > 0 {
                Button {
                    showsCommonGroups = true
                } label: {
                    LabeledContent("Groups in common", value: commonGroupCount.formatted())
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func identitySection(_ info: TelegramChatInfoData) -> some View {
        Section {
            VStack(spacing: 10) {
                avatar(info)
                Text(info.title)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                identityBadges(info)
                Text(identitySubtitle(info))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .accessibilityElement(children: .combine)

            Button("Search", systemImage: "magnifyingglass") {
                openConversationSearch()
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    @ViewBuilder private func identityBadges(_ info: TelegramChatInfoData) -> some View {
        if info.isScam || info.isFake || info.isVerified || info.isPremium {
            HStack(spacing: 6) {
                if info.isScam {
                    badgeCapsule("SCAM")
                }
                if info.isFake {
                    badgeCapsule("FAKE")
                }
                if info.isVerified {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.blue)
                        .accessibilityLabel("Verified")
                }
                if info.isPremium {
                    Image(systemName: "star.circle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Telegram Premium")
                }
            }
            .font(.subheadline)
        }
    }

    private func badgeCapsule(_ text: String) -> some View {
        Text(text)
            .font(.caption2.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.red, in: Capsule())
    }

    @ViewBuilder private func avatar(_ info: TelegramChatInfoData) -> some View {
        if info.isSavedMessages {
            Image(systemName: "bookmark.fill")
                .font(.system(size: 42))
                .foregroundStyle(.white)
                .frame(width: 96, height: 96)
                .background(Color.accentColor.gradient, in: Circle())
                .accessibilityHidden(true)
        } else if let avatarPath, let image = NSImage(contentsOfFile: avatarPath) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 96, height: 96)
                .clipShape(Circle())
                .accessibilityLabel("Profile photo")
        } else {
            Image(systemName: chat.kind.systemImage)
                .font(.system(size: 42))
                .frame(width: 96, height: 96)
                .background(.quaternary, in: Circle())
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder private func detailsSections(_ info: TelegramChatInfoData) -> some View {
        if !info.usernames.isEmpty || info.phoneNumber != nil || info.birthdate != nil || info.about != nil
            || info.personalChatId != 0
        {
            Section {
                if let phoneNumber = info.phoneNumber {
                    LabeledContent("Phone", value: phoneNumber)
                        .textSelection(.enabled)
                }
                if let username = info.usernames.first,
                   let url = URL(string: "https://t.me/\(username)")
                {
                    let isPublicChat = chat.kind == .group || chat.kind == .channel
                    profileLinkRow(
                        title: isPublicChat ? url.absoluteString : "@\(username)",
                        subtitle: isPublicChat ? publicLinkSubtitle(info.usernames) : usernameSubtitle(info.usernames),
                        url: url,
                        systemImage: isPublicChat ? "link" : "at",
                        copyValue: isPublicChat ? url.absoluteString : "@\(username)",
                    )
                }
                if let birthdate = info.birthdate {
                    LabeledContent("Birthdate", value: birthdate)
                }
                if info.personalChatId != 0 {
                    Button {
                        dismiss()
                        model.openLinkedChat(chatId: info.personalChatId)
                    } label: {
                        LabeledContent {
                            Text(info.personalChatTitle ?? "Open")
                        } label: {
                            Label("Channel", systemImage: "megaphone")
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if let about = info.about, !about.text.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(profileInformationLabel(info))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(macAttributedString(about))
                    }
                    .textSelection(.enabled)
                }
            }
        }

        if info.memberCount != nil || info.administratorCount != nil {
            Section {
                if let memberCount = info.memberCount {
                    chatMemberCountRow(
                        title: chat.kind == .channel ? "Subscribers" : "Members",
                        count: memberCount,
                        filter: .members,
                        enabled: info.canBrowseMembers,
                    )
                }
                if info.canManageMembers,
                   let administratorCount = info.administratorCount,
                   administratorCount > 0
                {
                    chatMemberCountRow(
                        title: "Administrators",
                        count: administratorCount,
                        filter: .administrators,
                        enabled: true,
                    )
                }
                if info.canRestrictMembers, let restrictedCount = info.restrictedCount, restrictedCount > 0 {
                    chatMemberCountRow(title: "Restricted", count: restrictedCount, filter: .restricted, enabled: true)
                }
                if info.canRestrictMembers, let bannedCount = info.bannedCount, bannedCount > 0 {
                    chatMemberCountRow(title: "Banned", count: bannedCount, filter: .banned, enabled: true)
                }
            }
        }

        groupSettingsSection(info)
    }

    @ViewBuilder private func groupSettingsSection(_ info: TelegramChatInfoData) -> some View {
        let isCommunity = chat.kind == .group || chat.kind == .channel
        let isChannel = chat.kind == .channel
        let showsLinkedChat = isCommunity && info.linkedChatId != 0
        let showsSlowMode = chat.kind == .group && info.slowModeDelay > 0
        let showsSignMessages = isChannel && info.canChangeInfo
        let showsHiddenMembers = isCommunity && info.canChangeInfo && info.hasHiddenMembers
        let showsReactions = isCommunity && info.reactionsSummary != nil
        let showsProtectedContent = isCommunity && info.hasProtectedContent
        if showsLinkedChat || showsSlowMode || showsSignMessages || showsProtectedContent
            || showsHiddenMembers || showsReactions
        {
            Section {
                if showsLinkedChat {
                    Button {
                        dismiss()
                        model.openLinkedChat(chatId: info.linkedChatId)
                    } label: {
                        LabeledContent(
                            isChannel ? "Discussion Group" : "Linked Channel",
                            value: info.linkedChatTitle ?? "Open",
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if showsSlowMode {
                    LabeledContent("Slow Mode", value: telegramSlowModeDescription(info.slowModeDelay))
                }
                if showsSignMessages {
                    LabeledContent("Sign Messages", value: info.signMessages ? "On" : "Off")
                }
                if showsReactions, let reactionsSummary = info.reactionsSummary {
                    LabeledContent("Reactions", value: reactionsSummary)
                }
                if showsHiddenMembers {
                    LabeledContent("Members", value: "Hidden")
                }
                if showsProtectedContent {
                    LabeledContent("Saving Content", value: "Restricted")
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

    @ViewBuilder private func chatMemberCountRow(
        title: String,
        count: Int,
        filter: TelegramChatInfoMemberFilter,
        enabled: Bool,
    ) -> some View {
        if enabled {
            Button {
                memberListFilter = filter
            } label: {
                LabeledContent(title, value: count.formatted())
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            LabeledContent(title, value: count.formatted())
        }
    }

    private func profileLinkRow(
        title: String,
        subtitle: String,
        url: URL,
        systemImage: String,
        copyValue: String,
    ) -> some View {
        Link(destination: url) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if copyValue != url.absoluteString {
                Button("Copy") { copyToPasteboard(copyValue) }
            }
            Button("Copy Link") { copyToPasteboard(url.absoluteString) }
        }
    }

    @ViewBuilder private func membersSection(_ info: TelegramChatInfoData) -> some View {
        if info.memberTotalCount > 0, info.memberTotalCount <= 5, !info.members.isEmpty {
            Section(chat.kind == .channel ? "Subscribers" : "Members") {
                ForEach(info.members) { member in
                    Button {
                        dismiss()
                        model.activateChatInfoMember(member.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(member.name)
                            let details = [member.role, member.presence].compactMap(\.self)
                            if !details.isEmpty {
                                Text(details.joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    // Without this, a `List` row built from multiple `Text` views reads as an
                    // empty cell to VoiceOver on macOS.
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    @ViewBuilder private func actionsSection(_ info: TelegramChatInfoData) -> some View {
        if hasActions(info) {
            Section {
                if canAddContact(info) {
                    Button("Add to Contacts", systemImage: "person.crop.circle.badge.plus") {
                        showsAddContact = true
                    }
                }
                if canStartSecretChat(info) {
                    Button("Start Secret Chat", systemImage: "lock.fill") {
                        confirmStartSecretChat = true
                    }
                }
                if info.blockableUserId != nil {
                    let blockTitle = info.isBot
                        ? (info.isBlocked ? "Restart Bot" : "Stop Bot")
                        : (info.isBlocked ? "Unblock User" : "Block User")
                    Button(blockTitle, role: info.isBlocked ? nil : .destructive) {
                        confirmBlock = true
                    }
                }
                if canReportChat {
                    let title = chat.kind == .privateChat ? "Report User" : "Report"
                    Button(title, role: .destructive) {
                        reportRequest = TelegramReportRequest(chatId: chat.chatId, messageIds: [], title: title)
                    }
                }
                if info.usesPrivacyCommand {
                    Button("Bot Privacy Policy") {
                        model.requestBotPrivacyPolicy(chatId: chat.chatId)
                        dismiss()
                    }
                } else if let privacyPolicyURL = info.privacyPolicyURL,
                          let url = URL(string: privacyPolicyURL)
                {
                    Link("Bot Privacy Policy", destination: url)
                }
                if info.canLeave {
                    Button(chat.kind == .channel ? "Leave Channel" : "Leave Group", role: .destructive) {
                        confirmLeave = true
                    }
                }
                if currentChat.actionPolicy.canClearHistory {
                    Button("Clear History", role: .destructive) {
                        showClearHistoryOptions = true
                    }
                }
                if shouldShowDeleteAction(info) {
                    Button(currentChat.actionPolicy.deleteActionTitle, role: .destructive) {
                        showDeleteOptions = true
                    }
                }
            }
        }
    }

    private static func autoDeleteLabel(_ seconds: Int) -> String {
        switch seconds {
        case 0: "Off"
        case 86400: "1 day"
        case 604_800: "1 week"
        case 2_678_400: "1 month"
        case let value where value % 86400 == 0: "\(value / 86400) days"
        default: "\(max(1, seconds / 3600)) hours"
        }
    }

    private func identitySubtitle(_ info: TelegramChatInfoData) -> String {
        if let status = model.conversationHeaderStatus, !status.isEmpty {
            return status
        }
        if chat.kind == .group || chat.kind == .channel, let memberCount = info.memberCount {
            let unit = chat.kind == .channel ? "subscriber" : "member"
            return "\(memberCount.formatted()) \(unit)\(memberCount == 1 ? "" : "s")"
        }
        return info.kind
    }

    private func canStartSecretChat(_ info: TelegramChatInfoData) -> Bool {
        chat.kind == .privateChat && !currentChat.isSavedMessages && info.privateChatUserId != nil
    }

    private func canAddContact(_ info: TelegramChatInfoData) -> Bool {
        info.privateChatUserId != nil && !info.isContact
    }

    private func profileInformationLabel(_ info: TelegramChatInfoData) -> String {
        if info.isBot {
            return "Bot Info"
        }
        return chat.kind == .group || chat.kind == .channel ? "Description" : "Bio"
    }

    private func openConversationSearch() {
        dismiss()
        Task { @MainActor in
            await Task.yield()
            model.beginConversationSearch()
        }
    }

    private func hasActions(_ info: TelegramChatInfoData) -> Bool {
        canStartSecretChat(info)
            || canAddContact(info)
            || info.blockableUserId != nil
            || canReportChat
            || info.usesPrivacyCommand
            || info.privacyPolicyURL != nil
            || info.canLeave
            || currentChat.actionPolicy.canClearHistory
            || shouldShowDeleteAction(info)
    }

    private func shouldShowDeleteAction(_ info: TelegramChatInfoData) -> Bool {
        switch chat.kind {
        case .privateChat, .secretChat:
            currentChat.canBeDeletedOnlyForSelf || currentChat.canBeDeletedForAllUsers
        case .channel, .group:
            info.canDeleteCommunity && currentChat.canBeDeletedForAllUsers
        }
    }

    private func usernameSubtitle(_ usernames: [String]) -> String {
        guard usernames.count > 1 else { return "Username" }
        return "Username. Also: \(usernames.dropFirst().map { "@\($0)" }.joined(separator: ", "))"
    }

    private func publicLinkSubtitle(_ usernames: [String]) -> String {
        guard usernames.count > 1 else { return "Link" }
        return "Link. Also: \(usernames.dropFirst().map { "@\($0)" }.joined(separator: ", "))"
    }

    private func copyToPasteboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private func loadInfo() async {
        isLoading = true
        let loaded = await model.loadChatInfo(for: chat)
        guard !Task.isCancelled else { return }
        info = loaded
        isLoading = false
        if let fileId = loaded?.photoFileId {
            avatarPath = await model.localPhotoPath(fileId: fileId)
        }
    }

    private func toggleBlock() {
        guard let current = info, let userId = current.blockableUserId else { return }
        Task {
            let blocked = !current.isBlocked
            guard await model.setChatInfoBlocked(blocked, userId: userId), !Task.isCancelled else { return }
            info?.isBlocked = blocked
        }
    }

    private func canEditAutoDelete(_ info: TelegramChatInfoData) -> Bool {
        guard !currentChat.isSavedMessages else { return false }
        switch chat.kind {
        case .privateChat, .secretChat:
            return true
        case .channel, .group:
            return info.canChangeInfo
        }
    }

    private func setAutoDelete(_ seconds: Int) {
        let previous = autoDeleteSeconds
        guard seconds != previous, !isSavingAutoDelete else { return }
        autoDeleteOverride = seconds
        isSavingAutoDelete = true
        let service = model.service
        let chatId = chat.chatId
        Task {
            defer { isSavingAutoDelete = false }
            do {
                _ = try await service.setChatMessageAutoDeleteTime(
                    chatId: chatId,
                    messageAutoDeleteTime: seconds,
                )
                info?.messageAutoDeleteTime = seconds
            } catch {
                autoDeleteOverride = previous
                errorMessage = telegramErrorDescription(error)
            }
        }
    }
}
