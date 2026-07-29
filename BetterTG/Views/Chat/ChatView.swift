// ChatView.swift

import Combine
import PhotosUI
import SwiftUI
import TDLibKit

// MARK: - ChatView

struct ChatView: View {
    // MARK: Lifecycle

    init(
        customChat: CustomChat,
        initialMessageId: Int64? = nil,
        movesAccessibilityFocusToInitialMessage: Bool = false,
    ) {
        let chatVM = ChatVM(
            customChat: customChat,
            initialMessageId: initialMessageId,
            movesAccessibilityFocusToInitialMessage: movesAccessibilityFocusToInitialMessage,
        )
        #if DEBUG
        if MockData.isEnabled, let user = customChat.user {
            let messages = MockData.makeMessages(chatId: customChat.chat.id, otherUser: user)
            chatVM.messages = messages
            customChat.lastMessage = messages.last?.message
        }
        #endif
        self._chatVM = State(wrappedValue: chatVM)
    }
    
    // MARK: Internal

    @AccessibilityFocusState var accessibilityFocusedMessageId: Int64?
    @Environment(\.isPreview) var isPreview
    @Environment(\.dismiss) var dismiss
    
    @FocusState var focused

    @State var chatVM: ChatVM
    
    var body: some View {
        @Bindable var chatVM = chatVM
        VStack(spacing: 0) {
            ScrollViewReader { scrollViewProxy in
                bodyView
                    .task { chatVM.start() }
                    .onAppear {
                        chatVM.scrollViewProxy = scrollViewProxy
                        positionInitialMessagesIfNeeded(using: scrollViewProxy)
                    }
                    .onChange(of: chatVM.initialMessagesLoaded) { _, loaded in
                        guard loaded else { return }
                        positionInitialMessagesIfNeeded(using: scrollViewProxy)
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

            if !isPreview {
                if chatVM.customChat.canPostMessages {
                    ChatBottomArea(focused: $focused)
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
        .navigationBarBackButtonHidden(true)
        .dropDestination(for: SelectedImage.self) { items, _ in
            nc.post(name: .localOnSelectedImagesDrop, object: Array(items.prefix(10)))
            return true
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarHeight($navigationBarHeight)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: dismiss.callAsFunction) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.backward")
                        Text(backButtonTitle)
                        if previousChatTitle == nil, unreadChatCount > 0 {
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
        .sheet(isPresented: $showsSharedMedia) {
            SharedMediaView(
                chatId: chatVM.customChat.chat.id,
                chatTitle: chatVM.customChat.chat.title,
                service: chatVM.service,
            ) { messageId in
                showsSharedMedia = false
                Task { @MainActor in
                    await Task.yield()
                    chatVM.navigateToMessage(id: messageId)
                }
            }
        }
        .sheet(isPresented: $showsChatInfo) {
            ChatInfoView {
                showsChatInfo = false
                Task { @MainActor in
                    await Task.yield()
                    showsSharedMedia = true
                }
            }
            .environment(chatVM)
        }
        .sheet(item: $chatVM.messagePendingForward) { message in
            ForwardChatPickerView(message: message, chatVM: chatVM)
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
                    distanceFromStart: index,
                    shouldShowProfileImage: chatVM.customChat.shouldShowProfileImage,
                    isPreview: isPreview,
                )
                .accessibilityFocused($accessibilityFocusedMessageId, equals: customMessage.id)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .listRowSpacing(5)
        .defaultScrollAnchor(.bottom)
        .background(.black)
        .scrollDismissesKeyboard(.interactively)
        .scrollBounceBehavior(.always)
        .scrollIndicators(.hidden)
        .scrollEdgeEffectHidden(true, for: .all)
        .onTapGesture { focused = false }
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.visibleRect.maxY >= geometry.contentSize.height - 20
        } action: { _, isAtBottom in
            guard !isPreview else { return }
            chatVM.updateBottomVisibility(isLastMessageVisible: isAtBottom)
        }
        .overlay(alignment: .top) {
            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: topGradientHeight)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .overlay(alignment: .bottom) {
            LinearGradient(colors: [.black, .clear], startPoint: .bottom, endPoint: .top)
                .frame(height: 24)
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

    @State private var navigationBarHeight = CGFloat.zero
    @State private var positionedInitialMessages = false
    @State private var rootVM = RootVM.shared
    @State private var showsSharedMedia = false
    @State private var showsChatInfo = false

    private var unreadChatCount: Int {
        rootVM.allChats.lazy.filter(\.hasUnreadMessages).count
    }

    private var previousChatTitle: String? {
        guard rootVM.path.count > 1,
              case .customChat(let chat, _, _) = rootVM.path[rootVM.path.count - 2]
        else { return nil }
        return chat.chat.title
    }

    private var backButtonTitle: String {
        previousChatTitle ?? "Chats"
    }

    private var backButtonAccessibilityLabel: String {
        if let previousChatTitle {
            return "Back to \(previousChatTitle)"
        }
        return "Back to chats, \(unreadChatCount) unread"
    }

    private var topGradientHeight: CGFloat {
        UIApplication.safeAreaInsets.top + navigationBarHeight
    }

    private var principal: some View {
        Button {
            showsChatInfo = true
        } label: {
            VStack(spacing: 0) {
                Text(chatVM.customChat.chat.title)

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
        .accessibilityHint("Opens chat information")
    }

    private func positionInitialMessagesIfNeeded(using scrollViewProxy: ScrollViewProxy) {
        guard chatVM.initialMessagesLoaded, !positionedInitialMessages else { return }
        positionedInitialMessages = true
        Task { @MainActor in
            // Allow List to commit the first history snapshot before positioning it.
            await Task.yield()
            await Task.yield()
            guard let targetId = chatVM.initialMessageId ?? chatVM.messages.last?.id else { return }
            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                scrollViewProxy.scrollTo(
                    targetId,
                    anchor: chatVM.initialMessageId == nil ? .bottom : .center,
                )
            }
            if chatVM.initialMessageId != nil {
                chatVM.highlightedMessageId = targetId
                if chatVM.movesAccessibilityFocusToInitialMessage {
                    accessibilityFocusedMessageId = targetId
                }
                Task.main(delay: 0.8) { chatVM.highlightedMessageId = nil }
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
    @Environment(ChatVM.self) private var chatVM

    let customMessage: CustomMessage
    let previousMessage: CustomMessage?
    let nextMessage: CustomMessage?
    let distanceFromStart: Int
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
        .onAppear { chatVM.loadMoreIfNeeded(distanceFromStart: distanceFromStart) }
    }

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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: Private

    private var title: String {
        "\(count) unread \(count == 1 ? "message" : "messages")"
    }
}
