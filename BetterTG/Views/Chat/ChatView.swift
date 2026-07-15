// ChatView.swift

import Combine
import PhotosUI
import SwiftUI
import TDLibKit

struct ChatView: View {
    // MARK: Lifecycle

    init(customChat: CustomChat, initialMessageId: Int64? = nil) {
        let chatVM = ChatVM(customChat: customChat, initialMessageId: initialMessageId)
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

    @Environment(\.isPreview) var isPreview
    @Environment(\.dismiss) var dismiss
    
    @FocusState var focused
    @AccessibilityFocusState var accessibilityFocusedMessageId: Int64?
    
    @State var chatVM: ChatVM
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { scrollViewProxy in
                bodyView
                    .onAppear {
                        chatVM.scrollViewProxy = scrollViewProxy
                        positionInitialMessagesIfNeeded(using: scrollViewProxy)
                    }
                    .onChange(of: chatVM.initialMessagesLoaded) { _, loaded in
                        guard loaded else { return }
                        positionInitialMessagesIfNeeded(using: scrollViewProxy)
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

            if !isPreview, chatVM.customChat.canPostMessages {
                ChatBottomArea(focused: $focused)
                    .readSize { chatVM.bottomAreaHeight = $0.height }
            }
        }
        .background(.black)
        .ignoresSafeArea(.container, edges: .top)
        .dropDestination(for: SelectedImage.self) { items, _ in
            nc.post(name: .localOnSelectedImagesDrop, object: Array(items.prefix(10)))
            return true
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarHeight($navigationBarHeight)
        .toolbar {
            ToolbarItem(placement: .principal) { principal }
            ToolbarItem(placement: .topBarTrailing) { topBarTrailing }
        }
        .alert(
            "Can't Open Destination",
            isPresented: Binding(
                get: { chatVM.navigationError != nil },
                set: { if !$0 { chatVM.navigationError = nil } },
            ),
        ) {
            Button("OK") { chatVM.navigationError = nil }
        } message: {
            Text(chatVM.navigationError ?? "The destination is unavailable.")
        }
        .environment(chatVM)
    }
    
    var bodyView: some View {
        List {
            ForEach(Array(chatVM.messages.enumerated()), id: \.element.id) { index, customMessage in
                if startsNewDay(at: index) {
                    MessageDayHeader(title: telegramMessageDayHeading(customMessage.message.date))
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                if unreadBoundaryMessageId == customMessage.id {
                    UnreadMessagesHeader(count: chatVM.initialUnreadCount)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                HStack(alignment: .bottom, spacing: 0) {
                    if customMessage.message.isOutgoing { Spacer(minLength: 0) } else {
                        if let user = customMessage.senderUser,
                           chatVM.customChat.shouldShowProfileImage
                        {
                            if chatVM.messages[safe: index + 1]?.senderUser?.id != user.id {
                                ProfileImageView(
                                    photo: user.profilePhoto?.big,
                                    minithumbnail: user.profilePhoto?.minithumbnail,
                                    title: user.firstName,
                                    userId: user.id,
                                )
                                .frame(width: 32, height: 32)
                                .accessibilityHidden(true)
                            } else {
                                Spacer()
                                    .frame(width: 32, height: 32)
                            }
                            Spacer()
                                .frame(width: 5)
                        }
                    }

                    MessageView(customMessage: customMessage)
                        .accessibilityFocused($accessibilityFocusedMessageId, equals: customMessage.id)
                        .frame(
                            maxWidth: Utils.maxMessageContentWidth,
                            alignment: customMessage.message.isOutgoing ? .trailing : .leading,
                        )
                        .onScrollVisibilityChange { visible in
                            guard !isPreview, visible else { return }
                            chatVM.viewMessage(id: customMessage.message.id)
                        }

                    if !customMessage.message.isOutgoing { Spacer(minLength: 0) }
                }
                .padding(customMessage.message.isOutgoing ? .trailing : .leading, 16)
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
                .onAppear { chatVM.loadMoreIfNeeded(for: customMessage) }
                .onScrollVisibilityChange { visible in
                    guard index == chatVM.messages.count - 1 else { return }
                    chatVM.updateBottomVisibility(isLastMessageVisible: visible)
                }
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
        .overlay(alignment: .bottomTrailing) {
            if chatVM.showScrollToBottomButton {
                scrollToBottomButton
                    .padding(.bottom, 8)
            }
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
                .padding(10)
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
        .padding(.trailing)
        .accessibilityLabel("Scroll to bottom")
        .accessibilityValue(
            chatVM.customChat.unreadCount == 0
                ? "No unread messages"
                : "\(chatVM.customChat.unreadCount) unread messages",
        )
    }
    
    // MARK: Private

    @State private var navigationBarHeight = CGFloat.zero
    @State private var positionedInitialMessages = false

    private var unreadBoundaryMessageId: Int64? {
        guard chatVM.initialUnreadCount > 0 else { return nil }
        return chatVM.messages.first { customMessage in
            !customMessage.message.isOutgoing
                && customMessage.id > chatVM.initialLastReadInboxMessageId
        }?.id
    }

    private func startsNewDay(at index: Int) -> Bool {
        guard chatVM.messages.indices.contains(index) else { return false }
        guard index > chatVM.messages.startIndex else { return true }
        let messageDate = Date(timeIntervalSince1970: TimeInterval(chatVM.messages[index].message.date))
        let previousDate = Date(timeIntervalSince1970: TimeInterval(chatVM.messages[index - 1].message.date))
        return !Calendar.autoupdatingCurrent.isDate(messageDate, inSameDayAs: previousDate)
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
                accessibilityFocusedMessageId = targetId
                Task.main(delay: 0.8) { chatVM.highlightedMessageId = nil }
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

    private var topGradientHeight: CGFloat {
        UIApplication.safeAreaInsets.top + navigationBarHeight
    }

    private var principal: some View {
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel(principalAccessibilityLabel)
        .accessibilityAddTraits(.isHeader)
    }

    private var principalAccessibilityLabel: String {
        let status = !chatVM.actionStatus.isEmpty ? chatVM.actionStatus : chatVM.onlineStatus
        return status.isEmpty ? chatVM.customChat.chat.title : "\(chatVM.customChat.chat.title), \(status)"
    }
    
    @ViewBuilder private var topBarTrailing: some View {
        let chat = chatVM.customChat.chat
        ProfileImageView(
            photo: chat.photo?.big,
            minithumbnail: chat.photo?.minithumbnail,
            title: chat.title,
            userId: chat.id,
        )
        .frame(width: 32, height: 32)
        .accessibilityHidden(true)
    }
}

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

private struct UnreadMessagesHeader: View {
    let count: Int

    private var title: String {
        "\(count) unread \(count == 1 ? "message" : "messages")"
    }

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
}
