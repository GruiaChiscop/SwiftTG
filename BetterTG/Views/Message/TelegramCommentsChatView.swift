// TelegramCommentsChatView.swift

import SwiftUI
import TDLibKit

// MARK: - TelegramCommentsChatView

/// A channel post's comment thread's messages live in the channel's linked discussion supergroup
/// (`getMessageThread` resolves which one, and its `messageThreadId`) - this hands off to the real
/// `ChatView`/`ChatVM` engine scoped to that thread via `messageTopic: .messageTopicThread(...)`,
/// matching Telegram-iOS, where comments reuse the full chat controller (attachments, polls,
/// replies, reactions, editing, forwarding...) rather than a bespoke reply list. `ChatView` itself
/// lives in this (iOS) target, so this wrapper is what iOS presents; macOS has its own equivalent
/// built on `MacConversationView` via `MacSessionModel.openCommentThread(...)`.
///
/// Takes an already-resolved `TelegramResolvedCommentsThread` rather than resolving it itself, so
/// the thread lookup happens before this is ever presented - mirroring Telegram-iOS's own
/// preload-then-navigate flow instead of opening an empty screen that fills in afterward.
struct TelegramCommentsChatView: View {
    let resolvedThread: TelegramResolvedCommentsThread

    var body: some View {
        NavigationStack {
            ChatView(
                customChat: resolvedThread.discussionChat,
                messageTopic: .messageTopicThread(MessageTopicThread(messageThreadId: resolvedThread.messageThreadId)),
                // The back button dismisses back to the channel post this thread was opened
                // from, not "to comments" (you're already there) - so it needs the channel's own
                // name, same as any other back button in the app.
                backButtonTitleOverride: resolvedThread.channelTitle,
                // Telegram-iOS shows "N Comments" as the page title itself, never the discussion
                // group's own name - the group identity is an implementation detail of where
                // comments are stored, not something the comments UI is meant to surface.
                titleOverride: resolvedThread.replyCount > 0
                    ? "\(resolvedThread.replyCount) Comment\(resolvedThread.replyCount == 1 ? "" : "s")"
                    : "Comments",
            )
        }
    }
}

// MARK: - TelegramResolvedCommentsThread

/// Result of resolving a channel post's comment thread (`service.getMessageThread` + looking up
/// the discussion group's `CustomChat`) - built before `TelegramCommentsChatView` is presented.
struct TelegramResolvedCommentsThread: Identifiable {
    let discussionChat: CustomChat
    let messageThreadId: Int64
    let channelTitle: String
    let replyCount: Int

    var id: Int64 { messageThreadId }
}
