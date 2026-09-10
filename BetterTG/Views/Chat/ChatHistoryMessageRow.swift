// ChatHistoryMessageRow.swift

import SwiftUI

// MARK: - ChatHistoryMessageRow

/// Keeps observation local to one hosted collection-view cell, so metadata changes do not rebuild
/// the entire history surface.
struct ChatHistoryMessageRow: View {
    let customMessage: CustomMessage
    let nextMessage: CustomMessage?
    let shouldShowProfileImage: Bool
    let messageAccessibilityFocused: AccessibilityFocusState<Int64?>.Binding

    var body: some View {
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
        .accessibilityFocused(messageAccessibilityFocused, equals: customMessage.id)
    }
}
