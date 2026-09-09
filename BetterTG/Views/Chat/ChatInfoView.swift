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
                videoChatSection
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
        .navigationDestination(isPresented: $showsCommonGroups) {
            if let userId = info?.commonGroupsUserId {
                ChatInfoCommonGroupsView(
                    userId: userId,
                    expectedCount: info?.commonGroupCount ?? 0,
                    service: chatVM.service,
                )
            }
        }
        .task(id: chat.id) {
            chatVM.refreshVideoChat()
            await loadInfo()
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
        .sheet(item: $reportRequest) { request in
            TelegramReportView(service: chatVM.service, request: request)
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
        .popover(isPresented: $showMuteOptions) {
            TelegramMutePresetPopoverContent { duration in
                setMuteDuration(duration)
                showMuteOptions = false
            }
            .presentationCompactAdaptation(.popover)
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
    }

    // MARK: Private

    @Environment(ChatVM.self) private var chatVM
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var errorMessage: String?
    @State private var info: TelegramChatInfoData?
    @State private var reportRequest: TelegramReportRequest?
    @State private var isLoading = true
    @State private var muteOverride: Bool?
    @State private var managedVideoChat: GroupCall?
    @State private var showDeleteConfirmation = false
    @State private var showClearHistoryConfirmation = false
    @State private var showLeaveConfirmation = false
    @State private var showMuteOptions = false
    @State private var showsCameraPermissionAlert = false
    @State private var showsCommonGroups = false
    @State private var showsMicrophonePermissionAlert = false
    @State private var showsScheduledMessages = false
    @State private var showsSharedMedia = false
    @State private var showsRtmpSetup = false
    @State private var showsVideoChatScheduler = false
    @State private var showsVideoChatStartOptions = false
    @State private var videoChatJoinCandidates: VideoChatJoinCandidates?

    private var chat: CustomChat { chatVM.customChat }

    /// The chat's video chat state is owned by `ChatVM` (kept live from `updateChatVideoChat`).
    private var videoChat: VideoChat { chatVM.videoChat }
    private var videoChatDetails: GroupCall? { chatVM.videoChatCall }
    private var hasActiveVideoChat: Bool { chatVM.hasActiveVideoChat }

    private var status: String {
        !chatVM.actionStatus.isEmpty ? chatVM.actionStatus : chatVM.onlineStatus
    }

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
                    .accessibilityHidden(true)
                    Text(chat.displayTitle)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)

                    let identityStatus = status.isEmpty ? chat.kind.title : status
                    Text(identityStatus)
                        .font(.subheadline)
                        .foregroundStyle(identityStatus == "online" ? .blue : .secondary)
                }
                .accessibilityElement(children: .combine)

                ChatInfoHeaderActionsView(
                    canStartAudioCall: info?.canStartAudioCall == true,
                    canStartVideoCall: info?.canStartVideoCall == true,
                    startAudioCall: startAudioCall,
                    startVideoCall: startVideoCall,
                    search: openConversationSearch,
                )
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
               info.commonGroupsUserId != nil
            {
                Button {
                    showsCommonGroups = true
                } label: {
                    LabeledContent("Groups in common", value: commonGroupCount.formatted())
                        .foregroundStyle(.primary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder private func profileInformationSection(_ info: TelegramChatInfoData) -> some View {
        if !info.usernames.isEmpty || info.phoneNumber != nil || info.birthdate != nil || info.about != nil {
            Section {
                if let phoneNumber = info.phoneNumber {
                    LabeledContent("Phone", value: phoneNumber)
                        .textSelection(.enabled)
                        .contextMenu {
                            Button("Copy Phone Number", systemImage: "doc.on.doc") {
                                UIPasteboard.general.string = phoneNumber
                            }
                            if let phoneURL = URL(string: "tel:\(phoneNumber.filter { $0.isNumber || $0 == "+" })") {
                                Link("Call with Phone", destination: phoneURL)
                            }
                        }
                        .accessibilityAction(named: "Copy Phone Number") {
                            UIPasteboard.general.string = phoneNumber
                        }
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
                Button("Copy username", systemImage: "doc.on.doc") { UIPasteboard.general.string = copyValue }
            }
            Button("Copy Link", systemImage: "link") { UIPasteboard.general.string = url.absoluteString }
        }
        .accessibilityActions {
            Button("Copy Link", systemImage: "link") { UIPasteboard.general.string = url.absoluteString }
            if copyValue != url.absoluteString {
                Button("Copy username", systemImage: "doc.on.doc") { UIPasteboard.general.string = copyValue }
            }
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
            )
        }
    }

    @ViewBuilder private func actionsSection(_ info: TelegramChatInfoData) -> some View {
        let policy = chat.actionPolicy
        if info.blockableUserId != nil
            || chat.chat.canBeReported
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

    private func startAudioCall() {
        guard let userId = info?.callUserId, info?.canStartAudioCall == true else { return }
        CallKitManager.shared.startOutgoingCall(
            userId: userId,
            displayName: chat.displayTitle,
            onMicrophonePermissionDenied: {
                showsMicrophonePermissionAlert = true
            },
        )
    }

    private func startVideoCall() {
        guard let userId = info?.callUserId, info?.canStartVideoCall == true else { return }
        CallKitManager.shared.startOutgoingCall(
            userId: userId,
            displayName: chat.displayTitle,
            isVideo: true,
            onMicrophonePermissionDenied: {
                showsMicrophonePermissionAlert = true
            },
            onCameraPermissionDenied: {
                showsCameraPermissionAlert = true
            },
        )
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
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
