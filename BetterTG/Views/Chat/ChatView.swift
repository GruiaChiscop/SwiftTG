// ChatView.swift

import Combine
import PhotosUI
import SwiftUI
import TDLibKit

// MARK: - PresentedChatActionError

private struct PresentedChatActionError: Identifiable {
    let id = UUID()
    let message: String
}

// MARK: - ChatInitialScrollTarget

private enum ChatInitialScrollTarget: Hashable {
    case unreadMessagesHeader
}

// MARK: - InitialScrollDestination

private enum InitialScrollDestination {
    case message(Int64, anchor: UnitPoint)
    case unreadMessagesHeader
}

// MARK: - ChatView

struct ChatView: View {
    // MARK: Lifecycle

    init(
        customChat: CustomChat,
        initialMessageId: Int64? = nil,
        movesAccessibilityFocusToInitialMessage: Bool = false,
        messageTopic: MessageTopic? = nil,
        backButtonTitleOverride: String? = nil,
        titleOverride: String? = nil,
    ) {
        let chatVM = ChatVM(
            customChat: customChat,
            initialMessageId: initialMessageId,
            movesAccessibilityFocusToInitialMessage: movesAccessibilityFocusToInitialMessage,
            messageTopic: messageTopic,
        )
        self._chatVM = State(wrappedValue: chatVM)
        self.backButtonTitleOverride = backButtonTitleOverride
        self.titleOverride = titleOverride
    }

    // MARK: Internal

    @AccessibilityFocusState var accessibilityFocusedMessageId: Int64?
    @Environment(\.isPreview) var isPreview
    @Environment(\.dismiss) var dismiss

    @FocusState var focused

    @State var chatVM: ChatVM

    /// Set when this chat was pushed from somewhere other than the root chat list/another chat
    /// (e.g. Chat Info's Members or Groups in Common) - `previousChatTitle` only knows how to look
    /// back through `rootVM.path`, which those screens deliberately don't push onto (see the
    /// comments in ChatInfoDetailViews.swift), so without this the back button falls back to a
    /// misleading "Chats" even though back doesn't actually go to the chat list.
    let backButtonTitleOverride: String?

    /// Telegram-iOS shows "N Comments" as the nav title for a comment thread rather than the
    /// underlying discussion group's own name, even though it's mechanically the same chat
    /// screen - set by `TelegramCommentsChatView` to match.
    let titleOverride: String?
    
    var body: some View {
        @Bindable var chatVM = chatVM
        @Bindable var videoNotePlayer = TelegramVideoNotePlayer.shared
        VStack(spacing: 0) {
            if chatVM.isConversationSearchActive {
                conversationSearchField
                Divider()
            } else {
                if chatVM.hasActiveVideoChat {
                    ChatVideoChatBannerView(
                        call: chatVM.videoChatCall,
                        isChannel: chatVM.customChat.kind == .channel,
                        join: joinActiveVideoChat,
                    )
                }
                ChatTopBannerView(chatVM: chatVM) {
                    showsPinnedMessages = true
                }
            }

            ScrollViewReader { scrollViewProxy in
                bodyView
                    .task {
                        chatVM.start()
                        await chatVM.favoriteStickers.load()
                    }
                    .onAppear {
                        chatVM.scrollViewProxy = scrollViewProxy
                    }
                    .task(id: chatVM.initialMessagesLoaded) {
                        guard chatVM.initialMessagesLoaded else { return }
                        await positionInitialMessagesIfNeeded(using: scrollViewProxy)
                    }
                    .onChange(of: chatVM.scrollRequestMessageId) { _, messageId in
                        guard let messageId else { return }
                        scrollToMessage(messageId, using: scrollViewProxy)
                    }
                    .onChange(of: chatVM.accessibilityFocusRequestMessageId) { _, messageId in
                        guard let messageId else { return }
                        focusMessage(messageId, using: scrollViewProxy)
                    }
            }
            .overlay {
                if chatVM.customChat.lastMessage == nil {
                    Text("No messages")
                        .frame(maxHeight: .infinity)
                        .background(.black)
                }
            }
            // Anchored to the message list itself (not the outer screen) so it stays part of the
            // messages region visually, not floating over the composer below.
            .overlay(alignment: .bottomTrailing) {
                if chatVM.showScrollToBottomButton {
                    scrollToBottomButton
                        .padding(8)
                }
            }
            .overlay {
                if chatVM.videoRecorder.usesScreenFlash {
                    Color.white
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            // `.overlay` alone doesn't create a new accessibility grouping level - without this,
            // VoiceOver still treats the button as a sibling of the composer below (since overlaid
            // content is flattened to the same level as its base view), regardless of which SwiftUI
            // view it's visually anchored to. `.contain` makes the messages + button one distinct
            // region, so the button is guaranteed to read as part of it, before the composer.
            .accessibilityElement(children: .contain)

            if chatVM.isConversationSearchActive {
                conversationSearchNavigationBar
            } else if !isPreview {
                if chatVM.customChat.canPostMessages || chatVM.isCommentThread {
                    ChatBottomArea(
                        focused: $focused,
                        voiceOverFocusRequest: composerVoiceOverFocusRequest,
                    ) {
                        guard let message = chatVM.messageActionError else { return }
                        presentedActionError = PresentedChatActionError(message: message)
                    }
                } else if chatVM.customChat.canJoin {
                    joinChatButton
                } else if chatVM.customChat.kind == .channel {
                    Text("Only channel administrators can post.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(.bar)
                }
            }
        }
        .background(.black)
        .ignoresSafeArea(.container, edges: .top)
        .navigationTitle(
            chatVM.isConversationSearchActive ? "" : (titleOverride ?? chatVM.customChat.displayTitle),
        )
        .navigationBarBackButtonHidden(true)
        .dropDestination(for: SelectedImage.self) { items, _ in
            nc.post(name: .localOnSelectedImagesDrop, object: Array(items.prefix(10)))
            return true
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .navigationBarHeight($navigationBarHeight)
        .onChange(of: chatVM.isConversationSearchActive) { _, isActive in
            if isActive {
                Task { @MainActor in
                    await Task.yield()
                    conversationSearchFocused = true
                }
            } else {
                conversationSearchFocused = false
            }
        }
        .onChange(of: chatVM.conversationSearchQuery) {
            chatVM.conversationSearchQueryDidChange()
        }
        .toolbar {
            if !chatVM.isConversationSearchActive {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: dismiss.callAsFunction) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.backward")
                            Text(backButtonTitle)
                            if backButtonTitleOverride == nil, previousChatTitle == nil, unreadChatCount > 0 {
                                Text("\(unreadChatCount)")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 5)
                                    .frame(minWidth: 18, minHeight: 18)
                                    .background(Color.accentColor, in: Capsule())
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    .accessibilityLabel(backButtonAccessibilityLabel)
                }
                ToolbarItem(placement: .principal) { principal }
                if callPeer != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("Audio Call", systemImage: "phone", action: startAudioCall)
                            Button("Video Call", systemImage: "video", action: startVideoCall)
                        } label: {
                            Label("Call", systemImage: "phone")
                        }
                    }
                }
            }
        }
        .alert(
            "Can't Open Destination",
            isPresented: Binding(
                get: { chatVM.navigationError != nil },
                set: {
                    if !$0 {
                        chatVM.navigationError = nil
                    }
                },
            ),
        ) {
            Button("OK") { chatVM.navigationError = nil }
        } message: {
            Text(chatVM.navigationError ?? "The destination is unavailable.")
        }
        .onChange(of: chatVM.messageActionError) { _, message in
            guard let message else { return }
            presentedActionError = PresentedChatActionError(message: message)
        }
        .alert(item: $presentedActionError) { error in
            Alert(
                title: Text("Action Failed"),
                message: Text(error.message),
                dismissButton: .default(Text("OK")) {
                    chatVM.messageActionError = nil
                },
            )
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
        .navigationDestination(isPresented: $showsChatInfo) {
            ChatInfoView()
                .environment(chatVM)
        }
        .sheet(item: $chatVM.messagePendingForward) { message in
            ForwardChatPickerView(message: message, chatVM: chatVM)
        }
        .sheet(isPresented: $showsPinnedMessages) {
            PinnedMessagesView()
                .environment(chatVM)
        }
        .fullScreenCover(isPresented: $videoNotePlayer.isPresentingViewOnce) {
            TelegramViewOnceVideoNotePlayerView(player: videoNotePlayer)
        }
        .environment(chatVM)
    }
    
    var bodyView: some View {
        let unreadMessageId = initialUnreadMessageId
        return List {
            ForEach(Array(chatVM.messages.enumerated()), id: \.element.id) { index, customMessage in
                ChatMessageListRows(
                    customMessage: customMessage,
                    previousMessage: chatVM.messages[safe: index - 1],
                    nextMessage: chatVM.messages[safe: index + 1],
                    shouldShowProfileImage: chatVM.customChat.shouldShowProfileImage,
                    isPreview: isPreview,
                    messageAccessibilityFocused: $accessibilityFocusedMessageId,
                    startsUnreadMessages: customMessage.id == unreadMessageId,
                    unreadHeaderVoiceOverFocusRequest: unreadHeaderVoiceOverFocusRequest,
                )
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 1)
        .listRowSpacing(5)
        .contentMargins(.bottom, 0, for: .scrollContent)
        .defaultScrollAnchor(.bottom)
        .scrollPosition($initialScrollPosition)
        .telegramChatWallpaper()
        .telegramMessageTextSize()
        .scrollDismissesKeyboard(.interactively)
        .scrollBounceBehavior(.always)
        .scrollIndicators(.hidden)
        .scrollEdgeEffectHidden(true, for: .all)
        .onTapGesture { focused = false }
        .onScrollGeometryChange(for: Bool.self) { geometry in
            // Hysteresis, not a single fixed threshold: self-sizing bubbles (images/link previews
            // resolving) make `contentSize.height` jitter by a few points on its own, which with
            // one threshold flipped this bool - and the button's visibility with it - back and
            // forth right as it settled at the bottom, so the button looked stuck mid-dismissal.
            // Once already at the bottom, tolerate more slack before counting that as "scrolled
            // away" again; only require the tight margin when actually approaching from above.
            let distanceFromBottom = geometry.contentSize.height - geometry.visibleRect.maxY
            let threshold: CGFloat = chatVM.isAtBottom ? 80 : 20
            return distanceFromBottom <= threshold
        } action: { _, isAtBottom in
            guard !isPreview else { return }
            chatVM.updateBottomVisibility(isLastMessageVisible: isAtBottom)
        }
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentSize.height > geometry.containerSize.height
                && geometry.visibleRect.minY <= 250
        } action: { wasNearTop, isNearTop in
            guard !isPreview, positionedInitialMessages, !wasNearTop, isNearTop else { return }
            chatVM.loadMessages()
        }
        .overlay(alignment: .top) {
            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: topGradientHeight)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    var joinChatButton: some View {
        Button {
            Task { await chatVM.joinCurrentChat() }
        } label: {
            HStack {
                Spacer()
                if chatVM.isJoiningChat {
                    ProgressView()
                } else {
                    Text(chatVM.customChat.kind == .channel ? "Join Channel" : "Join Group")
                        .font(.body.weight(.semibold))
                }
                Spacer()
            }
            .padding(12)
            .contentShape(Rectangle())
        }
        .disabled(chatVM.isJoiningChat)
        .background(.bar)
    }

    var scrollToBottomButton: some View {
        Button(action: chatVM.scrollToLast) {
            Image(systemName: "chevron.down")
                .offset(y: 1)
                .font(.title3)
                .frame(width: 48, height: 48)
                .background(.black)
                .clipShape(.circle)
                .overlay {
                    Circle()
                        .stroke(.blue, lineWidth: 1)
                }
                .overlay(alignment: .top) {
                    if chatVM.customChat.unreadCount != 0 {
                        Circle()
                            .fill(.blue)
                            .frame(width: 16, height: 16)
                            .overlay {
                                Text("\(chatVM.customChat.unreadCount)")
                                    .font(.caption)
                                    .foregroundStyle(.white)
                                    .minimumScaleFactor(0.5)
                            }
                            .offset(y: -5)
                            .accessibilityHidden(true)
                    }
                }
        }
        .buttonStyle(.plain)
        .transition(.move(edge: .bottom).combined(with: .scale).combined(with: .opacity))
        .accessibilityLabel("Scroll to bottom")
        .accessibilityValue(
            Text("\(chatVM.customChat.unreadCount) unread messages"),
            isEnabled: chatVM.customChat.unreadCount != 0,
        )
        .accessibilitySortPriority(-1)
    }
    
    // MARK: Private

    @Environment(\.openURL) private var openURL
    @FocusState private var conversationSearchFocused
    @State private var initialScrollPosition = ScrollPosition(idType: Int64.self, edge: .bottom)
    @State private var composerVoiceOverFocusRequest = 0
    @State private var navigationBarHeight = CGFloat.zero
    @State private var positionedInitialMessages = false
    @State private var rootVM = RootVM.shared
    @State private var showsChatInfo = false
    @State private var showsPinnedMessages = false
    @State private var showsCameraPermissionAlert = false
    @State private var showsMicrophonePermissionAlert = false
    @State private var presentedActionError: PresentedChatActionError?
    @State private var unreadHeaderVoiceOverFocusRequest = 0

    private var unreadChatCount: Int {
        rootVM.allChats.lazy.filter(\.hasUnreadMessages).count
    }

    private var previousChatTitle: String? {
        guard rootVM.path.count > 1,
              case .customChat(let chat, _, _) = rootVM.path[rootVM.path.count - 2]
        else { return nil }
        return chat.displayTitle
    }

    private var backButtonTitle: String {
        backButtonTitleOverride ?? previousChatTitle ?? "Chats"
    }

    private var backButtonAccessibilityLabel: String {
        if let backButtonTitleOverride {
            return "Back to \(backButtonTitleOverride)"
        }
        if let previousChatTitle {
            return "Back to \(previousChatTitle)"
        }
        return "Back to chats, \(unreadChatCount) unread"
    }

    private var topGradientHeight: CGFloat {
        UIApplication.safeAreaInsets.top + navigationBarHeight
    }

    private var initialUnreadMessageId: Int64? {
        guard chatVM.initialUnreadCount > 0 else { return nil }
        return chatVM.messages
            .first {
                !$0.message.isOutgoing && $0.id > chatVM.initialLastReadInboxMessageId
            }?.id
    }

    /// Calls (Phase 1) are 1:1 only - no button for bots, groups, or channels.
    private var callPeer: (id: Int64, displayName: String)? {
        guard case .user(let user) = chatVM.customChat.type else { return nil }
        let name = [user.firstName, user.lastName].filter { !$0.isEmpty }.joined(separator: " ")
        return (id: user.id, displayName: name.isEmpty ? chatVM.customChat.displayTitle : name)
    }

    private var principalAccessibilityLabel: String {
        let title = titleOverride ?? chatVM.customChat.displayTitle
        let status = chatVM.actionStatus.isEmpty ? chatVM.conversationStatus : chatVM.actionStatus
        return status.isEmpty ? title : "\(title), \(status)"
    }

    private var conversationSearchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField(
                "Search messages",
                text: Binding(
                    get: { chatVM.conversationSearchQuery },
                    set: { chatVM.conversationSearchQuery = $0 },
                ),
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($conversationSearchFocused)
            .submitLabel(.search)

            Button("Cancel", role: .cancel) {
                chatVM.endConversationSearch()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var conversationSearchNavigationBar: some View {
        HStack(spacing: 12) {
            if chatVM.isSearchingConversation {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
            }

            Text(chatVM.conversationSearchStatus)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Search results, \(chatVM.conversationSearchStatus)")

            Spacer()

            Button("Older result", systemImage: "chevron.up") {
                chatVM.selectOlderConversationSearchResult()
            }
            .labelStyle(.iconOnly)
            .disabled(!chatVM.canSelectOlderConversationSearchResult || chatVM.isSearchingConversation)

            Button("Newer result", systemImage: "chevron.down") {
                chatVM.selectNewerConversationSearchResult()
            }
            .labelStyle(.iconOnly)
            .disabled(!chatVM.canSelectNewerConversationSearchResult || chatVM.isSearchingConversation)
        }
        .frame(minHeight: 44)
        .padding(.horizontal, 12)
        .background(.bar)
    }

    private var principal: some View {
        Button {
            showsChatInfo = true
        } label: {
            VStack(spacing: 0) {
                Text(titleOverride ?? chatVM.customChat.displayTitle)

                Group {
                    if !chatVM.actionStatus.isEmpty {
                        Text(chatVM.actionStatus)
                    } else if !chatVM.conversationStatus.isEmpty {
                        Text(chatVM.conversationStatus)
                    }
                }
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .top),
                        removal: .move(edge: .bottom),
                    )
                    .combined(with: .opacity),
                )
                .font(.caption)
                // `telegramUserPresenceDescription` emits "Online" (capitalised).
                .foregroundStyle(!chatVM.actionStatus.isEmpty || chatVM.onlineStatus == "Online" ? .blue : .gray)
            }
            .frame(minWidth: Utils.screen.bounds.width * 0.5)
            .padding(.horizontal, 12)
            .frame(height: 44)
            .glassEffect(.regular.interactive())
        }
        .buttonStyle(.plain)
        // `.combine` re-derives this element from its children, and the animated status Text
        // above is inserted/removed (not just updated) whenever actionStatus/onlineStatus
        // changes - a structural accessibility-tree change VoiceOver treats as noteworthy enough
        // to move focus here, stealing it away from wherever the user actually was (e.g. mid-way
        // through "Show All Pinned Messages"). An explicit, always-present label sidesteps that:
        // the same element just gets a new string, which VoiceOver applies silently in place.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(principalAccessibilityLabel)
        .accessibilityAddTraits(.isHeader)
    }

    private func startAudioCall() {
        guard let callPeer else { return }
        CallKitManager.shared.startOutgoingCall(
            userId: callPeer.id,
            displayName: callPeer.displayName,
            onMicrophonePermissionDenied: {
                showsMicrophonePermissionAlert = true
            },
        )
    }

    private func joinActiveVideoChat() {
        let videoChat = chatVM.videoChat
        guard videoChat.groupCallId != 0 else { return }
        Task { @MainActor in
            let session = TelegramCallSession.shared
            if session.groupCallCoordinator != nil {
                session.restoreCallView()
                return
            }

            let scheduled = chatVM.videoChatCall?.scheduledStartDate ?? 0 > 0
            if scheduled, chatVM.videoChatCall?.canBeManaged != true {
                do {
                    _ = try await chatVM.service.toggleVideoChatEnabledStartNotification(
                        enabledStartNotification: !(chatVM.videoChatCall?.enabledStartNotification ?? false),
                        groupCallId: videoChat.groupCallId,
                    )
                } catch {
                    presentedActionError = PresentedChatActionError(message: telegramErrorDescription(error))
                }
                return
            }

            let joined = await session.joinVideoChat(
                groupCallId: videoChat.groupCallId,
                participantId: videoChat.defaultParticipantId,
                startScheduled: scheduled,
            )
            if !joined {
                presentedActionError = PresentedChatActionError(
                    message: "This voice chat couldn't be opened.",
                )
            }
        }
    }

    private func startVideoCall() {
        guard let callPeer else { return }
        CallKitManager.shared.startOutgoingCall(
            userId: callPeer.id,
            displayName: callPeer.displayName,
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

    private func positionInitialMessagesIfNeeded(using scrollViewProxy: ScrollViewProxy) async {
        guard chatVM.initialMessagesLoaded, !positionedInitialMessages else { return }
        positionedInitialMessages = true

        let scrollDestination: InitialScrollDestination?
        let accessibilityTarget: InitialAccessibilityTarget
        if let initialMessageId = chatVM.initialMessageId {
            scrollDestination = .message(initialMessageId, anchor: .center)
            accessibilityTarget = chatVM.movesAccessibilityFocusToInitialMessage
                ? .message(initialMessageId)
                : .none
        } else if initialUnreadMessageId != nil {
            scrollDestination = .unreadMessagesHeader
            accessibilityTarget = .unreadHeader
        } else {
            scrollDestination = chatVM.messages.last.map { .message($0.id, anchor: .bottom) }
            accessibilityTarget =
                if !isPreview, chatVM.customChat.canPostMessages || chatVM.isCommentThread {
                    .composer
                } else if let lastMessageId = chatVM.messages.last?.id {
                    .message(lastMessageId)
                } else {
                    .none
                }
        }

        // `initialMessagesLoaded` flips true the same tick `messages` is populated. Give List time
        // to create its rows before scrolling, then another layout pass before assigning VoiceOver
        // focus. This task is attached to the view, so leaving the chat cancels the sequence.
        await Task.yield()
        await Task.yield()
        guard !Task.isCancelled else { return }
        if let scrollDestination {
            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                switch scrollDestination {
                case .message(let messageId, let anchor):
                    scrollViewProxy.scrollTo(messageId, anchor: anchor)
                case .unreadMessagesHeader:
                    scrollViewProxy.scrollTo(ChatInitialScrollTarget.unreadMessagesHeader, anchor: .top)
                }
            }
        }

        guard UIAccessibility.isVoiceOverRunning, accessibilityTarget != .none else { return }
        await Task.yield()
        await Task.yield()
        guard !Task.isCancelled else { return }
        switch accessibilityTarget {
        case .composer:
            composerVoiceOverFocusRequest += 1
        case .message(let messageId):
            accessibilityFocusedMessageId = nil
            await Task.yield()
            guard !Task.isCancelled else { return }
            accessibilityFocusedMessageId = messageId
        case .none:
            break
        case .unreadHeader:
            unreadHeaderVoiceOverFocusRequest += 1
        }
    }

    private func scrollToMessage(_ messageId: Int64, using scrollViewProxy: ScrollViewProxy) {
        Task { @MainActor in
            await Task.yield()
            var transaction = Transaction()
            transaction.animation = .default
            withTransaction(transaction) {
                scrollViewProxy.scrollTo(messageId, anchor: .center)
                chatVM.highlightedMessageId = messageId
            }
            chatVM.scrollRequestMessageId = nil
            Task.main(delay: 0.8) {
                withAnimation { chatVM.highlightedMessageId = nil }
            }
        }
    }

    private func focusMessage(_ messageId: Int64, using scrollViewProxy: ScrollViewProxy) {
        Task { @MainActor in
            // Let List create the requested row before assigning accessibility focus.
            await Task.yield()
            await Task.yield()
            var transaction = Transaction()
            transaction.animation = UIAccessibility.isVoiceOverRunning ? nil : .default
            withTransaction(transaction) {
                scrollViewProxy.scrollTo(messageId, anchor: .center)
                chatVM.highlightedMessageId = messageId
            }
            await Task.yield()
            accessibilityFocusedMessageId = nil
            await Task.yield()
            accessibilityFocusedMessageId = messageId
            chatVM.accessibilityFocusRequestMessageId = nil
            Task.main(delay: 0.8) {
                withAnimation { chatVM.highlightedMessageId = nil }
            }
        }
    }
}

// MARK: - ChatMessageListRows

/// Keeps per-message observation local so a metadata update does not invalidate
/// and rebuild the entire chat list.
private struct ChatMessageListRows: View {
    // MARK: Internal

    let customMessage: CustomMessage
    let previousMessage: CustomMessage?
    let nextMessage: CustomMessage?
    let shouldShowProfileImage: Bool
    let isPreview: Bool
    let messageAccessibilityFocused: AccessibilityFocusState<Int64?>.Binding
    let startsUnreadMessages: Bool
    let unreadHeaderVoiceOverFocusRequest: Int

    var body: some View {
        if startsNewDay {
            MessageDayHeader(title: telegramMessageDayHeading(customMessage.message.date))
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }

        if startsUnreadMessages {
            UnreadMessagesHeader(
                count: chatVM.initialUnreadCount,
                voiceOverFocusRequest: unreadHeaderVoiceOverFocusRequest,
            )
            .id(ChatInitialScrollTarget.unreadMessagesHeader)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }

        HStack(alignment: .bottom, spacing: 0) {
            if customMessage.serviceMessageText != nil || customMessage.message.isOutgoing {
                Spacer(minLength: 0)
            } else if let user = customMessage.senderUser, shouldShowProfileImage {
                if nextMessage?.senderUser?.id != user.id {
                    ProfileImageView(
                        photo: user.profilePhoto?.big,
                        minithumbnail: user.profilePhoto?.minithumbnail,
                        title: user.firstName,
                        userId: user.id,
                    )
                    .frame(width: 32, height: 32)
                    .accessibilityHidden(true)
                } else {
                    Spacer().frame(width: 32, height: 32)
                }
                Spacer().frame(width: 5)
            }

            MessageView(customMessage: customMessage)
                .frame(
                    maxWidth: Utils.maxMessageContentWidth,
                    alignment: customMessage.serviceMessageText != nil
                        ? .center
                        : (customMessage.message.isOutgoing ? .trailing : .leading),
                )
                .onScrollVisibilityChange { visible in
                    guard !isPreview, visible else { return }
                    chatVM.viewMessage(id: customMessage.message.id)
                }

            if customMessage.serviceMessageText != nil || !customMessage.message.isOutgoing {
                Spacer(minLength: 0)
            }
        }
        .padding(
            customMessage.serviceMessageText != nil
                ? .horizontal
                : (customMessage.message.isOutgoing ? .trailing : .leading),
            16,
        )
        .transition(
            .asymmetric(
                insertion: .move(edge: .bottom),
                removal: .move(edge: customMessage.message.isOutgoing ? .trailing : .leading),
            )
            .combined(with: .opacity),
        )
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .id(customMessage.id)
        .accessibilityFocused(messageAccessibilityFocused, equals: customMessage.id)
    }

    // MARK: Private

    @Environment(ChatVM.self) private var chatVM

    private var startsNewDay: Bool {
        guard let previousMessage else { return true }
        let date = Date(timeIntervalSince1970: TimeInterval(customMessage.message.date))
        let previousDate = Date(timeIntervalSince1970: TimeInterval(previousMessage.message.date))
        return !Calendar.autoupdatingCurrent.isDate(date, inSameDayAs: previousDate)
    }
}

// MARK: - InitialAccessibilityTarget

private enum InitialAccessibilityTarget: Equatable {
    case composer
    case message(Int64)
    case none
    case unreadHeader
}

// MARK: - MessageDayHeader

private struct MessageDayHeader: View {
    let title: String

    var body: some View {
        HStack {
            Spacer()
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial, in: Capsule())
            Spacer()
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - UnreadMessagesHeader

private struct UnreadMessagesHeader: View {
    // MARK: Internal

    let count: Int
    let voiceOverFocusRequest: Int

    var body: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(.blue.opacity(0.6))
                .frame(height: 1)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.blue)
                .fixedSize()
            Rectangle()
                .fill(.blue.opacity(0.6))
                .frame(height: 1)
        }
        .padding(.vertical, 6)
        .accessibilityHidden(true)
        .overlay {
            VoiceOverFocusTarget(
                label: title,
                traits: .header,
                request: voiceOverFocusRequest,
            )
        }
    }

    // MARK: Private

    private var title: String {
        "\(count) unread \(count == 1 ? "message" : "messages")"
    }
}
