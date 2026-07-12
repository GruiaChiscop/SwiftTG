// ChatView.swift

import Combine
import PhotosUI
import SwiftUI
import TDLibKit

struct ChatView: View {
    // MARK: Lifecycle

    init(customChat: CustomChat) {
        let chatVM = ChatVM(customChat: customChat)
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
    
    @State var chatVM: ChatVM
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { scrollViewProxy in
                bodyView.onAppear { chatVM.scrollViewProxy = scrollViewProxy }
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
        .environment(chatVM)
    }
    
    var bodyView: some View {
        List {
            ForEach(Array(chatVM.messages.enumerated()), id: \.element.id) { index, customMessage in
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
                            } else {
                                Spacer()
                                    .frame(width: 32, height: 32)
                            }
                            Spacer()
                                .frame(width: 5)
                        }
                    }

                    MessageView(customMessage: customMessage)
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
                }
            }
            .transition(.move(edge: .bottom).combined(with: .scale).combined(with: .opacity))
            .padding(.trailing)
            .onTapGesture(perform: chatVM.scrollToLast)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                chatVM.customChat.unreadCount != 0
                    ? "Scroll to Bottom, \(chatVM.customChat.unreadCount) unread"
                    : "Scroll to Bottom",
            )
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { chatVM.scrollToLast() }
    }
    
    // MARK: Private

    @State private var navigationBarHeight = CGFloat.zero

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
    }
}
