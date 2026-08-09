// TelegramComments.swift

import SwiftUI

// MARK: - TelegramCommentsBar

/// The "N Comments" row shown under a channel post that has a linked discussion group - matches
/// where official Telegram puts it, at the bottom of the post rather than as a separate action.
struct TelegramCommentsBar: View {
    let replyCount: Int
    /// Set while the tap target is resolving the discussion thread before navigating - matches
    /// Telegram-iOS, which preloads the thread and only then pushes the comments screen, rather
    /// than opening a screen that fills in after the fact.
    var isLoading = false
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: "bubble.left")
                Text(replyCount > 0 ? "\(replyCount) Comment\(replyCount == 1 ? "" : "s")" : "Leave a Comment")
                    .font(.footnote.weight(.medium))
                Spacer()
                if isLoading {
                    ProgressView()
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.tint)
        .disabled(isLoading)
    }
}
