// ChatInfoView.swift

import SwiftUI
import TDLibKit
import UIKit

// MARK: - ChatInfoView

struct ChatInfoView: View {
    // MARK: Internal

    var body: some View {
        List {
            ChatInfoIdentitySection(
                info: info,
                onMicrophonePermissionDenied: { showsMicrophonePermissionAlert = true },
                onCameraPermissionDenied: { showsCameraPermissionAlert = true },
            )

            if let info {
                ChatInfoProfileInformationSection(info: info)
                ChatInfoNotificationsSection(
                    isMuted: isMuted(info),
                    onMuteButtonTapped: {
                        if isMuted(info) {
                            setMuteDuration(0)
                        } else {
                            showMuteOptions = true
                        }
                    },
                )
                ChatInfoAutoDeleteSection(info: info) { errorMessage = $0 }
                videoChatSection
                ChatInfoMemberDetailsSection(info: info) { membersFilter = $0 }
                ChatInfoMembersPreviewSection(info: info)
                ChatInfoGroupSettingsSection(info: info)
                ChatInfoSharedContentSection(
                    info: info,
                    onOpenSharedMedia: { showsSharedMedia = true },
                    onOpenScheduledMessages: { showsScheduledMessages = true },
                    onOpenCommonGroups: { showsCommonGroups = true },
                )
                ChatInfoUnofficialAppWarningSection(info: info)
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
        .navigationDestination(item: $membersFilter) { filter in
            ChatInfoMembersView(
                chatId: chat.id,
                isChannel: chat.kind == .channel,
                filter: filter,
                service: chatVM.service,
            )
        }
        .navigationDestination(isPresented: $showsCommonGroups) {
            if let info, let userId = info.commonGroupsUserId {
                ChatInfoCommonGroupsView(
                    userId: userId,
                    expectedCount: info.commonGroupCount ?? 0,
                    service: chatVM.service,
                )
            }
        }
        .task(id: chat.id) {
            chatVM.refreshVideoChat()
            await loadInfo()
        }
        .sheet(item: $reportRequest) { request in
            TelegramReportView(service: chatVM.service, request: request)
        }
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
        .alert("Camera Access Required", isPresented: $showsCameraPermissionAlert) {
            Button("Open Settings", action: openSettings)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Allow camera access in Settings to start video calls.")
        }
        .alert("Microphone Access Required", isPresented: $showsMicrophonePermissionAlert) {
            Button("Open Settings", action: openSettings)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Allow microphone access in Settings to make calls.")
        }
        .sheet(isPresented: $showsAddContact) {
            if let info, let userId = info.privateChatUserId {
                AddContactSheet(
                    userId: userId,
                    firstName: info.contactFirstName,
                    lastName: info.contactLastName,
                    phoneNumber: info.phoneNumber,
                    service: chatVM.service,
                ) {
                    self.info?.isContact = true
                }
            }
        }
        .sheet(item: $videoChatJoinCandidates) { candidates in
            VideoChatJoinAsPicker(
                chatId: chat.id,
                candidates: candidates,
                service: chatVM.service,
            ) { sender in
                Task { await performVideoChatJoin(participantId: sender) }
            }
        }
        .sheet(isPresented: $showsVideoChatScheduler) {
            NavigationStack {
                VideoChatScheduleView(
                    chatId: chat.id,
                    service: chatVM.service,
                ) { call in
                    applyCreatedVideoChat(call)
                }
            }
        }
        .sheet(isPresented: $showsRtmpSetup) {
            NavigationStack {
                VideoChatRtmpView(
                    chatId: chat.id,
                    service: chatVM.service,
                    createsStream: true,
                ) { call in
                    applyCreatedVideoChat(call)
                }
            }
        }
        .alert("Start \(videoChatTitle)", isPresented: $showsVideoChatStartOptions) {
            Button("Start Now") {
                startVideoChat()
            }
            Button("Schedule") {
                showsVideoChatScheduler = true
            }
            Button("Stream with...") {
                showsRtmpSetup = true
            }
            Button("Cancel", role: .cancel) {}
        }
        .navigationDestination(item: $managedVideoChat) { call in
            VideoChatManagementView(
                chatId: chat.id,
                service: chatVM.service,
                initialCall: call,
            ) { updated in
                if let updated {
                    chatVM.videoChatCall = updated
                } else {
                    chatVM.refreshVideoChat()
                }
            }
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
        .alert("Clear history in \(chat.displayTitle)?", isPresented: $showClearHistoryConfirmation) {
            if chat.chat.canBeDeletedOnlyForSelf {
                Button("Clear only for me", role: .destructive) { clearHistory(forEveryone: false) }
            }
            if chat.chat.canBeDeletedForAllUsers {
                Button("Clear for everyone", role: .destructive) { clearHistory(forEveryone: true) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All messages will be removed, but the chat will remain in your chat list.")
        }
        .alert(
            "\(chat.actionPolicy.leaveActionTitle ?? "Leave") \(chat.displayTitle)?",
            isPresented: $showLeaveConfirmation,
        ) {
            Button(chat.kind == .channel ? "Leave Channel" : "Leave Group", role: .destructive) {
                leaveChat()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You will leave this chat and it will be removed from your chat list.")
        }
        .alert("Start Secret Chat", isPresented: $showsStartSecretChatConfirmation) {
            Button("Start") { startSecretChat() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Start a secret chat with \(chat.displayTitle)?")
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
    @Environment(\.openURL) private var openURL

    @State private var errorMessage: String?
    @State private var info: TelegramChatInfoData?
    @State private var reportRequest: TelegramReportRequest?
    @State private var isLoading = true
    @State private var managedVideoChat: GroupCall?
    @State private var showDeleteConfirmation = false
    @State private var showClearHistoryConfirmation = false
    @State private var showLeaveConfirmation = false
    @State private var showsStartSecretChatConfirmation = false
    @State private var isStartingSecretChat = false
    @State private var showsAddContact = false
    @State private var showsSharedMedia = false
    @State private var showsScheduledMessages = false
    @State private var showsCommonGroups = false
    @State private var membersFilter: TelegramChatInfoMemberFilter?
    @State private var showMuteOptions = false
    @State private var muteOverride: Bool?
    @State private var showsCameraPermissionAlert = false
    @State private var showsMicrophonePermissionAlert = false
    @State private var showsRtmpSetup = false
    @State private var showsVideoChatScheduler = false
    @State private var showsVideoChatStartOptions = false
    @State private var videoChatJoinCandidates: VideoChatJoinCandidates?

    private var chat: CustomChat { chatVM.customChat }

    /// The chat's video chat state is owned by `ChatVM` (kept live from `updateChatVideoChat`).
    private var videoChat: VideoChat { chatVM.videoChat }
    private var videoChatDetails: GroupCall? { chatVM.videoChatCall }
    private var hasActiveVideoChat: Bool { chatVM.hasActiveVideoChat }

    private var videoChatTitle: String {
        chat.kind == .channel ? "Live Stream" : "Voice Chat"
    }

    private var canManageVideoChats: Bool {
        let status: ChatMemberStatus?
        switch chat.type {
        case .group(let group):
            status = group.status
        case .supergroup(let supergroup):
            status = supergroup.status
        case .bot, .user:
            return false
        }
        switch status {
        case .chatMemberStatusCreator:
            return true
        case .chatMemberStatusAdministrator(let administrator):
            return administrator.rights.canManageVideoChats
        default:
            return false
        }
    }

    @ViewBuilder private var videoChatSection: some View {
        if chat.kind == .group || chat.kind == .channel,
           hasActiveVideoChat || canManageVideoChats
           || (videoChatDetails?.scheduledStartDate ?? 0) > 0 {
            Section(chat.kind == .channel ? "Live Stream" : "Voice Chat") {
                if let videoChatDetails, videoChatDetails.scheduledStartDate > 0 {
                    LabeledContent(
                        "Scheduled",
                        value: Foundation.Date(
                            timeIntervalSince1970: TimeInterval(videoChatDetails.scheduledStartDate),
                        )
                        .formatted(date: .abbreviated, time: .shortened),
                    )
                }

                if hasActiveVideoChat, let videoChatDetails {
                    if videoChatDetails.scheduledStartDate > 0 {
                        if videoChatDetails.canBeManaged {
                            Button {
                                startScheduledVideoChat()
                            } label: {
                                Label("Start Now", systemImage: "play.fill")
                            }
                        }
                        Button {
                            toggleVideoChatReminder()
                        } label: {
                            Label(
                                videoChatDetails.enabledStartNotification ? "Turn Off Reminder" : "Set Reminder",
                                systemImage: videoChatDetails.enabledStartNotification ? "bell.slash" : "bell",
                            )
                        }
                    } else {
                        Button {
                            joinVideoChat()
                        } label: {
                            Label(
                                "Join \(videoChatTitle)",
                                systemImage: chat.kind == .channel
                                    ? "dot.radiowaves.left.and.right"
                                    : "waveform",
                            )
                        }
                    }
                    if videoChatDetails.canBeManaged {
                        Button {
                            managedVideoChat = videoChatDetails
                        } label: {
                            Label("Manage \(videoChatTitle)", systemImage: "slider.horizontal.3")
                        }
                    }
                } else if canManageVideoChats {
                    Button {
                        showsVideoChatStartOptions = true
                    } label: {
                        Label(
                            "Start \(videoChatTitle)",
                            systemImage: chat.kind == .channel ? "dot.radiowaves.left.and.right" : "waveform",
                        )
                    }
                }
            }
        }
    }

    private var canStartSecretChat: Bool {
        chat.kind == .privateChat && !chat.isSavedMessages && info?.privateChatUserId != nil
    }

    private var canAddContact: Bool {
        guard let info else { return false }
        return info.privateChatUserId != nil && !info.isContact
    }

    @ViewBuilder private func actionsSection(_ info: TelegramChatInfoData) -> some View {
        let policy = chat.actionPolicy
        if canStartSecretChat
            || canAddContact
            || info.blockableUserId != nil
            || chat.chat.canBeReported
            || policy.canLeave
            || policy.canClearHistory
            || policy.canDeleteChat
        {
            Section {
                if canAddContact {
                    Button("Add to Contacts", systemImage: "person.crop.circle.badge.plus") {
                        showsAddContact = true
                    }
                }

                if canStartSecretChat {
                    Button("Start Secret Chat", systemImage: "lock.fill") {
                        showsStartSecretChatConfirmation = true
                    }
                    .disabled(isStartingSecretChat)
                }

                if info.blockableUserId != nil {
                    Button(
                        blockActionTitle(info),
                        role: info.isBlocked ? nil : .destructive,
                    ) {
                        toggleBlocked()
                    }
                }

                if chat.chat.canBeReported {
                    let title = chat.kind == .privateChat ? "Report User" : "Report"
                    Button(title, role: .destructive) {
                        reportRequest = TelegramReportRequest(chatId: chat.id, messageIds: [], title: title)
                    }
                }

                if let leaveTitle = policy.leaveActionTitle {
                    Button(leaveTitle, role: .destructive) {
                        showLeaveConfirmation = true
                    }
                }

                if policy.canClearHistory {
                    Button("Clear History", role: .destructive) {
                        showClearHistoryConfirmation = true
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

    private func deleteChat(forAll: Bool) {
        RootVM.shared.deleteChat(chat, forAll: forAll)
        dismiss()
    }

    private func clearHistory(forEveryone: Bool) {
        RootVM.shared.clearHistory(chat, forEveryone: forEveryone)
        dismiss()
    }

    private func leaveChat() {
        RootVM.shared.leave(chat)
        dismiss()
    }

    private func startSecretChat() {
        guard let userId = info?.privateChatUserId, !isStartingSecretChat else { return }
        isStartingSecretChat = true
        let service = chatVM.service
        Task {
            defer { isStartingSecretChat = false }
            do {
                let chat = try await service.createNewSecretChat(userId: userId)
                guard let customChat = await RootVM.shared.getCustomChat(from: chat.id) else {
                    errorMessage = "The secret chat was created but couldn't be opened."
                    return
                }
                dismiss()
                await Task.yield()
                RootVM.shared.navigate(to: .customChat(customChat))
            } catch {
                errorMessage = telegramErrorDescription(error)
            }
        }
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

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }

    private func blockActionTitle(_ info: TelegramChatInfoData) -> String {
        if info.isBot {
            return info.isBlocked ? "Restart Bot" : "Stop Bot"
        }
        return info.isBlocked ? "Unblock User" : "Block User"
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

    private func startVideoChat() {
        Task { @MainActor in
            let started = await TelegramCallSession.shared.createVideoChat(chatId: chat.id)
            if !started {
                errorMessage = "The \(videoChatTitle.lowercased()) couldn't be started. Check microphone access and make sure no other call is active."
            }
        }
    }

    private func joinVideoChat() {
        guard hasActiveVideoChat else { return }
        Task { @MainActor in
            if TelegramCallSession.shared.groupCallCoordinator != nil {
                TelegramCallSession.shared.restoreCallView()
                return
            }
            let identities = await chatVM.videoChatJoinIdentities()
            if identities.count > 1 {
                videoChatJoinCandidates = VideoChatJoinCandidates(senders: identities)
                return
            }
            await performVideoChatJoin(participantId: identities.first ?? videoChat.defaultParticipantId)
        }
    }

    private func performVideoChatJoin(participantId: MessageSender?) async {
        let joined = await TelegramCallSession.shared.joinVideoChat(
            groupCallId: videoChat.groupCallId,
            participantId: participantId,
        )
        if !joined {
            errorMessage = "The \(videoChatTitle.lowercased()) couldn't be opened."
        }
    }

    private func startScheduledVideoChat() {
        guard hasActiveVideoChat else { return }
        Task { @MainActor in
            let joined = await TelegramCallSession.shared.joinVideoChat(
                groupCallId: videoChat.groupCallId,
                participantId: videoChat.defaultParticipantId,
                startScheduled: true,
            )
            if !joined {
                errorMessage = "The \(videoChatTitle.lowercased()) couldn't be started."
            }
        }
    }

    private func toggleVideoChatReminder() {
        guard let videoChatDetails else { return }
        Task { @MainActor in
            do {
                _ = try await chatVM.service.toggleVideoChatEnabledStartNotification(
                    enabledStartNotification: !videoChatDetails.enabledStartNotification,
                    groupCallId: videoChatDetails.id,
                )
                chatVM.refreshVideoChat()
            } catch {
                errorMessage = telegramErrorDescription(error)
            }
        }
    }

    private func applyCreatedVideoChat(_ call: GroupCall) {
        chatVM.applyCreatedVideoChat(call)
    }
}
