// MacChatList.swift

import SwiftUI
import TDLibKit

struct MacChatRow: View {
    // MARK: Internal

    @Bindable var model: MacSessionModel

    let chat: ChatListItemState
    let chatList: ChatList
    let isOpen: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: chat.kind.systemImage)
                .foregroundStyle(isOpen ? Color.accentColor : .secondary)
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(chat.title)
                        .fontWeight(chat.unreadCount > 0 ? .semibold : .regular)
                        .lineLimit(1)
                    Spacer()
                    if let message = chat.lastMessage {
                        Text(Date(timeIntervalSince1970: TimeInterval(message.date)), format: .dateTime.hour().minute())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Text(chat.lastMessage.map(macMessageText) ?? "No messages")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    if chat.unreadCount > 0 {
                        Text("\(chat.unreadCount)")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.accentColor, in: Capsule())
                    }
                }
            }
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Press Return or Space to open this chat")
        .accessibilityActions { chatActions }
        .contextMenu { chatActions }
        .confirmationDialog("Mute \(chat.title)", isPresented: $showMuteOptions) {
            ForEach(TelegramMutePreset.allCases) { preset in
                Button(preset.title) { model.setMuteDuration(preset.duration, for: chat) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete \(chat.title)?", isPresented: $showDeleteOptions) {
            if chat.actionPolicy.canDeleteCommunity {
                Button("Delete for everyone", role: .destructive) {
                    Task { _ = await model.deleteCommunityFromInfo(chat) }
                }
            } else if chat.canBeDeletedOnlyForSelf {
                Button("Delete only for me", role: .destructive) {
                    model.deleteChat(chat, forEveryone: false)
                }
            }
            if chat.actionPolicy.membership != .creator, chat.canBeDeletedForAllUsers {
                Button("Delete for everyone", role: .destructive) {
                    model.deleteChat(chat, forEveryone: true)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Clear history in \(chat.title)?", isPresented: $showClearHistoryOptions) {
            if chat.canBeDeletedOnlyForSelf {
                Button("Clear only for me", role: .destructive) {
                    model.clearChatHistory(chat, forEveryone: false)
                }
            }
            if chat.canBeDeletedForAllUsers {
                Button("Clear for everyone", role: .destructive) {
                    model.clearChatHistory(chat, forEveryone: true)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All messages will be removed, but the chat will remain in your chat list.")
        }
        .confirmationDialog("Leave \(chat.title)?", isPresented: $showLeaveConfirmation) {
            Button(chat.kind == .channel ? "Leave Channel" : "Leave Group", role: .destructive) {
                model.leaveChat(chat)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You will leave this chat and it will be removed from your chat list.")
        }
    }

    // MARK: Private

    @State private var showClearHistoryOptions = false
    @State private var showDeleteOptions = false
    @State private var showLeaveConfirmation = false
    @State private var showMuteOptions = false

    private var accessibilityLabel: String {
        var parts = [String]()
        if let kind = chat.kind.accessibilityTitle {
            parts.append(kind)
        }
        parts.append(chat.title)
        if chat.unreadCount > 0 {
            parts.append("\(chat.unreadCount) unread")
        }
        if chat.isMarkedAsUnread {
            parts.append("Marked as unread")
        }
        if let lastMessage = chat.lastMessage {
            parts.append(macMessageText(lastMessage))
            parts.append(telegramMessageDateDescription(lastMessage.date))
        } else {
            parts.append("No messages")
        }
        if isMuted {
            parts.append("Muted")
        }
        if isPinned {
            parts.append("Pinned")
        }
        if isArchived {
            parts.append("Archived")
        }
        if isOpen {
            parts.append("Open")
        }
        return parts.joined(separator: ", ")
    }

    private var isMuted: Bool {
        (chat.notificationSettings?.muteFor ?? 0) > 0
    }

    private var isPinned: Bool {
        chat.position(in: chatList)?.isPinned == true
    }

    private var isArchived: Bool {
        chat.position(in: .chatListArchive) != nil
    }

    @ViewBuilder private var chatActions: some View {
        let policy = chat.actionPolicy
        Button(
            chat.hasUnreadMessages ? "Mark as Read" : "Mark as Unread",
            systemImage: chat.hasUnreadMessages ? "envelope.open" : "envelope.badge",
        ) {
            model.toggleRead(for: chat)
        }

        Button(isMuted ? "Unmute" : "Mute", systemImage: isMuted ? "speaker.wave.2" : "speaker.slash") {
            if isMuted {
                model.setMuteDuration(0, for: chat)
            } else {
                showMuteOptions = true
            }
        }

        Button(isPinned ? "Unpin" : "Pin", systemImage: isPinned ? "pin.slash.fill" : "pin.fill") {
            model.togglePinned(for: chat, in: chatList)
        }

        Button(isArchived ? "Unarchive" : "Archive", systemImage: isArchived ? "tray.and.arrow.up" : "archivebox") {
            model.toggleArchived(chat)
        }

        if policy.canClearHistory || policy.canLeave || policy.canDeleteChat {
            Divider()
        }
        if policy.canClearHistory {
            Button("Clear History", systemImage: "eraser", role: .destructive) {
                showClearHistoryOptions = true
            }
        }
        if let leaveTitle = policy.leaveActionTitle {
            Button(
                leaveTitle,
                systemImage: "rectangle.portrait.and.arrow.right",
                role: .destructive,
            ) {
                showLeaveConfirmation = true
            }
        } else if policy.canDeleteChat {
            Button(policy.deleteActionTitle, systemImage: "trash", role: .destructive) {
                showDeleteOptions = true
            }
        }
    }
}
