// ChatHistoryRowView.swift

import SwiftUI

// MARK: - ChatHistoryRowView

struct ChatHistoryRowView: View {
    let item: ChatHistoryItem
    let shouldShowProfileImage: Bool
    let messageAccessibilityFocused: AccessibilityFocusState<Int64?>.Binding

    var body: some View {
        switch item.kind {
        case .day(let title):
            MessageDayHeader(title: title)
        case .message(let message, _, let next):
            ChatHistoryMessageRow(
                customMessage: message,
                nextMessage: next,
                shouldShowProfileImage: shouldShowProfileImage,
                messageAccessibilityFocused: messageAccessibilityFocused,
            )
        case .unread(let count, let request):
            UnreadMessagesHeader(count: count, voiceOverFocusRequest: request)
        }
    }
}
