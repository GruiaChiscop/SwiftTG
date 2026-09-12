// ChatHistoryCollectionView.swift

import SwiftUI

// MARK: - ChatHistoryCollectionView

struct ChatHistoryCollectionView: UIViewControllerRepresentable {
    // MARK: Internal

    let chatVM: ChatVM
    let messages: [CustomMessage]
    let unreadMessageId: Int64?
    let shouldShowProfileImage: Bool
    let isPreview: Bool
    let canLoadOlderMessages: Bool
    let canMarkMessagesRead: Bool
    let unreadHeaderVoiceOverFocusRequest: Int
    let navigator: ChatHistoryNavigator
    let messageAccessibilityFocused: AccessibilityFocusState<Int64?>.Binding
    let onBackgroundTap: () -> Void
    let onScrollButtonFocused: () -> Void

    static func dismantleUIViewController(
        _ controller: ChatHistoryCollectionViewController,
        coordinator _: Void,
    ) {
        controller.navigatorDidDismantle()
    }

    func makeUIViewController(context _: Context) -> ChatHistoryCollectionViewController {
        ChatHistoryCollectionViewController(navigator: navigator)
    }

    func updateUIViewController(_ controller: ChatHistoryCollectionViewController, context _: Context) {
        controller.update(ChatHistoryCollectionViewController.Configuration(
            chatVM: chatVM,
            messages: messages,
            unreadMessageId: unreadMessageId,
            unreadCount: chatVM.initialUnreadCount,
            currentUnreadCount: chatVM.conversationUnreadCount,
            unreadHeaderVoiceOverFocusRequest: unreadHeaderVoiceOverFocusRequest,
            shouldShowProfileImage: shouldShowProfileImage,
            isPreview: isPreview,
            canLoadOlderMessages: canLoadOlderMessages,
            canMarkMessagesRead: canMarkMessagesRead,
            messageAccessibilityFocused: messageAccessibilityFocused,
            focusedMessageId: messageAccessibilityFocused.wrappedValue,
            dynamicTypeSize: dynamicTypeSize,
            bubbleCornerRadius: bubbleCornerRadius,
            colorScheme: colorScheme,
            layoutDirection: layoutDirection,
            reduceMotion: reduceMotion,
            onBackgroundTap: onBackgroundTap,
            onScrollButtonFocused: onScrollButtonFocused,
        ))
    }

    // MARK: Private

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.telegramBubbleCornerRadius) private var bubbleCornerRadius
}
