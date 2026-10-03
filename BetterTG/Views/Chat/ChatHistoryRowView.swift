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
        case .message(let message, let previous, let next):
            ChatHistoryMessageRow(
                customMessage: message,
                previousMessage: previous,
                nextMessage: next,
                shouldShowProfileImage: shouldShowProfileImage,
                messageAccessibilityFocused: messageAccessibilityFocused,
            )
        case .unread(let count, _):
            UnreadMessagesHeader(count: count)
        }
    }
}
