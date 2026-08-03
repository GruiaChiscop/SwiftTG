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
        .confirmationDialog("Mute \(chat.title)", isPresented: $showMuteOptions) {
            ForEach(TelegramMutePreset.allCases) { preset in
                Button(preset.title) { model.setMuteDuration(preset.duration, for: currentChat) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Leave \(chat.title)?", isPresented: $confirmLeave) {
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
        .confirmationDialog(blockDialogTitle, isPresented: $confirmBlock) {
            Button(blockConfirmationTitle, role: info?.isBlocked == true ? nil : .destructive) {
                toggleBlock()
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(deleteDialogTitle, isPresented: $showDeleteOptions) {
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
        .confirmationDialog("Clear history in \(chat.title)?", isPresented: $showClearHistoryOptions) {
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
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @State private var avatarPath: String?
    @State private var confirmBlock = false
    @State private var confirmLeave = false
    @State private var info: TelegramChatInfoData?
    @State private var isLoading = true
    @State private var memberListFilter: TelegramChatInfoMemberFilter?
    @State private var showClearHistoryOptions = false
    @State private var showDeleteOptions = false
    @State private var showMuteOptions = false
    @State private var showsCommonGroups = false
    @State private var showsSharedMedia = false

    private var currentChat: ChatListItemState {
        model.chatList.items[chat.chatId] ?? chat
    }

    private var isMuted: Bool {
        guard let settings = currentChat.notificationSettings else {
            return (info?.defaultMuteFor ?? 0) > 0
        }
        return settings.useDefaultMuteFor
            ? (info?.defaultMuteFor ?? 0) > 0
            : settings.muteFor > 0
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
        "\(currentChat.actionPolicy.deleteActionTitle) \(chat.title)?"
    }

    private func sharedMediaSection(_ info: TelegramChatInfoData) -> some View {
        Section {
            Button("Shared Media", systemImage: "photo.on.rectangle") {
                showsSharedMedia = true
            }
            .accessibilityHint("Shows media, files, links, music, and voice messages")

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
                Text(model.conversationHeaderStatus ?? info.kind)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .accessibilityElement(children: .combine)

            Button(isMuted ? "Unmute" : "Mute", systemImage: isMuted ? "bell.slash.fill" : "bell.fill") {
                if isMuted {
                    model.setMuteDuration(0, for: currentChat)
                } else {
                    showMuteOptions = true
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Button("Search", systemImage: "magnifyingglass") {
                openConversationSearch()
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    @ViewBuilder private func avatar(_: TelegramChatInfoData) -> some View {
        if let avatarPath, let image = NSImage(contentsOfFile: avatarPath) {
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
        if !info.usernames.isEmpty || info.phoneNumber != nil || info.birthdate != nil || info.about != nil {
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
                }
            }
        }
    }

    @ViewBuilder private func actionsSection(_ info: TelegramChatInfoData) -> some View {
        if hasActions(info) {
            Section {
                if info.blockableUserId != nil {
                    let blockTitle = info.isBot
                        ? (info.isBlocked ? "Restart Bot" : "Stop Bot")
                        : (info.isBlocked ? "Unblock User" : "Block User")
                    Button(blockTitle, role: info.isBlocked ? nil : .destructive) {
                        confirmBlock = true
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
        info.blockableUserId != nil
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
}

// MARK: - MacSessionModel Chat Info

extension MacSessionModel {
    func loadChatInfo(for state: ChatListItemState) async -> TelegramChatInfoData? {
        try? await TelegramChatInfoLoader(service: service).load(chatId: state.chatId)
    }

    func setChatInfoBlocked(_ blocked: Bool, userId: Int64) async -> Bool {
        messageActionError = nil
        do {
            _ = try await service.setMessageSenderBlockList(
                blockList: blocked ? .blockListMain : nil,
                senderId: .messageSenderUser(.init(userId: userId)),
            )
            return true
        } catch {
            messageActionError = error.localizedDescription
            return false
        }
    }

    func leaveChatFromInfo(_ chat: ChatListItemState) async -> Bool {
        messageActionError = nil
        do {
            _ = try await service.leaveChat(chatId: chat.chatId)
            _ = try await service.deleteChatHistory(
                chatId: chat.chatId,
                removeFromChatList: true,
                revoke: false,
            )
            return true
        } catch {
            messageActionError = error.localizedDescription
            return false
        }
    }

    func deleteCommunityFromInfo(_ chat: ChatListItemState) async -> Bool {
        messageActionError = nil
        do {
            _ = try await service.deleteChat(chatId: chat.chatId)
            return true
        } catch {
            messageActionError = error.localizedDescription
            return false
        }
    }

    func activateChatInfoMember(_ senderId: MessageSender) {
        Task { [weak self] in
            guard let self else { return }
            let chat: Chat? =
                switch senderId {
                case .messageSenderUser(let value):
                    try? await service.createPrivateChat(force: false, userId: value.userId)
                case .messageSenderChat(let value):
                    try? await service.getChat(chatId: value.chatId)
                }
            guard let chat else {
                messageActionError = "This member is private or unavailable."
                return
            }
            await activateResolvedChat(chat, messageId: nil)
        }
    }

    func activateChatInfoChat(_ chat: Chat) {
        Task { [weak self] in
            await self?.activateResolvedChat(chat, messageId: nil)
        }
    }

    func requestBotPrivacyPolicy(chatId: Int64) {
        performMessageAction {
            _ = try await self.service.sendMessage(
                chatId: chatId,
                inputMessageContent: .inputMessageText(.init(
                    clearDraft: false,
                    linkPreviewOptions: nil,
                    text: FormattedText(entities: [], text: "/privacy"),
                )),
                options: nil,
                replyMarkup: nil,
                replyTo: nil,
                topicId: nil,
            )
        }
    }
}
