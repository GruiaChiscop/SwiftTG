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

// MARK: - ChatView

struct ChatView: View {
    // MARK: Lifecycle

    init(
        customChat: CustomChat,
        initialMessageId: Int64? = nil,
        movesAccessibilityFocusToInitialMessage: Bool = false,
        backButtonTitleOverride: String? = nil,
    ) {
        let chatVM = ChatVM(
            customChat: customChat,
            initialMessageId: initialMessageId,
            movesAccessibilityFocusToInitialMessage: movesAccessibilityFocusToInitialMessage,
        )
        self._chatVM = State(wrappedValue: chatVM)
        self.backButtonTitleOverride = backButtonTitleOverride
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
    
    var body: some View {
        @Bindable var chatVM = chatVM
        VStack(spacing: 0) {
            if chatVM.isConversationSearchActive {
                conversationSearchField
                Divider()
            } else if chatVM.showsChatTranslationBanner || chatVM.isChatTranslationEnabled {
                chatTranslationBanner
                Divider()
            } else if chatVM.currentPinnedMessage != nil {
                pinnedMessageBanner
                Divider()
            }

            ScrollViewReader { scrollViewProxy in
                bodyView
                    .task { chatVM.start() }
                    .onAppear {
                        chatVM.scrollViewProxy = scrollViewProxy
                        positionInitialMessagesIfNeeded()
                    }
                    .onChange(of: chatVM.initialMessagesLoaded) { _, loaded in
                        guard loaded else { return }
                        positionInitialMessagesIfNeeded()
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
            // `.overlay` alone doesn't create a new accessibility grouping level - without this,
            // VoiceOver still treats the button as a sibling of the composer below (since overlaid
            // content is flattened to the same level as its base view), regardless of which SwiftUI
            // view it's visually anchored to. `.contain` makes the messages + button one distinct
            // region, so the button is guaranteed to read as part of it, before the composer.
            .accessibilityElement(children: .contain)

            if chatVM.isConversationSearchActive {
                conversationSearchNavigationBar
            } else if !isPreview {
                if chatVM.customChat.canPostMessages {
                    ChatBottomArea(focused: $focused) {
                        guard let message = chatVM.messageActionError else { return }
                        presentedActionError = PresentedChatActionError(message: message)
                    }
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
        .navigationTitle(chatVM.isConversationSearchActive ? "" : chatVM.customChat.displayTitle)
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
        .environment(chatVM)
    }
    
    var bodyView: some View {
        List {
            ForEach(Array(chatVM.messages.enumerated()), id: \.element.id) { index, customMessage in
                ChatMessageListRows(
                    customMessage: customMessage,
                    previousMessage: chatVM.messages[safe: index - 1],
                    nextMessage: chatVM.messages[safe: index + 1],
                    shouldShowProfileImage: chatVM.customChat.shouldShowProfileImage,
                    isPreview: isPreview,
                )
                .accessibilityFocused($accessibilityFocusedMessageId, equals: customMessage.id)
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

    @FocusState private var conversationSearchFocused
    @State private var initialScrollPosition = ScrollPosition(idType: Int64.self, edge: .bottom)
    @State private var navigationBarHeight = CGFloat.zero
    @State private var positionedInitialMessages = false
    @State private var rootVM = RootVM.shared
    @State private var showsChatInfo = false
    @State private var showsPinnedMessages = false
    @State private var presentedActionError: PresentedChatActionError?

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

    private var pinnedMessageSummary: String {
        guard let message = chatVM.currentPinnedMessage else { return "" }
        return telegramQuotedMessageExcerpt(telegramMessageContentDescription(message))
    }

    private var detectedChatLanguageName: String {
        guard let code = chatVM.detectedChatLanguage else { return "" }
        return Locale.current.localizedString(forLanguageCode: code) ?? code
    }

    private var initialUnreadMessageId: Int64? {
        guard chatVM.initialUnreadCount > 0 else { return nil }
        return chatVM.messages
            .first {
                !$0.message.isOutgoing && $0.id > chatVM.initialLastReadInboxMessageId
            }?.id
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

    private var chatTranslationBanner: some View {
        HStack(spacing: 8) {
            if chatVM.isChatTranslationEnabled {
                Text("Translated from \(detectedChatLanguageName)")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Show Original") {
                    chatVM.disableChatTranslation()
                }
                .font(.subheadline)
            } else {
                Text("Translate from \(detectedChatLanguageName)?")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Dismiss", systemImage: "xmark") {
                    chatVM.dismissChatTranslationSuggestion()
                }
                .labelStyle(.iconOnly)
                Button("Translate") {
                    chatVM.enableChatTranslation()
                }
                .font(.subheadline.weight(.semibold))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private var pinnedMessageBanner: some View {
        HStack(spacing: 8) {
            Button {
                guard let message = chatVM.currentPinnedMessage else { return }
                chatVM.navigateToMessage(id: message.id)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pinned Message")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tint)
                    Text(pinnedMessageSummary)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button("Show All Pinned Messages", systemImage: "chevron.right") {
                showsPinnedMessages = true
            }
            .labelStyle(.iconOnly)
            .frame(width: 44, height: 44)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
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
                Text(chatVM.customChat.displayTitle)

                Group {
                    if !chatVM.actionStatus.isEmpty {
                        Text(chatVM.actionStatus)
                    } else if !chatVM.onlineStatus.isEmpty {
                        Text(chatVM.onlineStatus)
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
                .foregroundStyle(!chatVM.actionStatus.isEmpty || chatVM.onlineStatus == "online" ? .blue : .gray)
            }
            .frame(minWidth: Utils.screen.bounds.width * 0.5)
            .padding(.horizontal, 12)
            .frame(height: 44)
            .glassEffect(.regular.interactive())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func positionInitialMessagesIfNeeded() {
        guard chatVM.initialMessagesLoaded, !positionedInitialMessages else { return }
        positionedInitialMessages = true

        let focusMessageId: Int64?
        let anchor: UnitPoint
        if let initialMessageId = chatVM.initialMessageId {
            focusMessageId = initialMessageId
            anchor = .center
        } else if let initialUnreadMessageId {
            focusMessageId = initialUnreadMessageId
            anchor = .top
        } else {
            focusMessageId = chatVM.messages.last?.id
            anchor = .bottom
        }

        Task { @MainActor in
            // `initialMessagesLoaded` flips true the same tick `messages` is populated - List
            // (UITableView-backed) hasn't necessarily created/laid out those rows yet, so a
            // `scrollTo` issued synchronously here can silently land nowhere.
            await Task.yield()
            await Task.yield()
            guard let focusMessageId else { return }
            // Scrolls to the exact id, via the same `ScrollViewReader` proxy `focusMessage`/
            // `scrollToMessage` already rely on - `initialScrollPosition`'s edge-based
            // `.scrollTo(edge: .bottom)` doesn't guarantee *which* row ends up laid out, only
            // that the scroll offset ends up near the bottom.
            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                chatVM.scrollViewProxy?.scrollTo(focusMessageId, anchor: anchor)
            }
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

    var body: some View {
        if startsNewDay {
            MessageDayHeader(title: telegramMessageDayHeading(customMessage.message.date))
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }

        if startsUnreadMessages {
            UnreadMessagesHeader(count: chatVM.initialUnreadCount)
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
    }

    // MARK: Private

    @Environment(ChatVM.self) private var chatVM

    private var startsNewDay: Bool {
        guard let previousMessage else { return true }
        let date = Date(timeIntervalSince1970: TimeInterval(customMessage.message.date))
        let previousDate = Date(timeIntervalSince1970: TimeInterval(previousMessage.message.date))
        return !Calendar.autoupdatingCurrent.isDate(date, inSameDayAs: previousDate)
    }

    private var startsUnreadMessages: Bool {
        guard chatVM.initialUnreadCount > 0,
              !customMessage.message.isOutgoing,
              customMessage.id > chatVM.initialLastReadInboxMessageId
        else { return false }
        guard let previousMessage else { return true }
        return previousMessage.message.isOutgoing
            || previousMessage.id <= chatVM.initialLastReadInboxMessageId
    }
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
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: Private

    private var title: String {
        "\(count) unread \(count == 1 ? "message" : "messages")"
    }
}
