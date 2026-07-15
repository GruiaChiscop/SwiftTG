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
            Image(systemName: "bubble.left.fill")
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
            Button("Mute for 1 hour") { model.setMuteDuration(60 * 60, for: chat) }
            Button("Mute for 8 hours") { model.setMuteDuration(8 * 60 * 60, for: chat) }
            Button("Mute for 2 days") { model.setMuteDuration(2 * 24 * 60 * 60, for: chat) }
            Button("Mute forever") { model.setMuteDuration(Int(Int32.max), for: chat) }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete \(chat.title)?", isPresented: $showDeleteOptions) {
            if chat.canBeDeletedOnlyForSelf {
                Button("Delete only for me", role: .destructive) {
                    model.deleteChat(chat, forEveryone: false)
                }
            }
            if chat.canBeDeletedForAllUsers {
                Button("Delete for everyone", role: .destructive) {
                    model.deleteChat(chat, forEveryone: true)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: Private

    @State private var showDeleteOptions = false
    @State private var showMuteOptions = false

    private var accessibilityLabel: String {
        var parts = [chat.title, chat.lastMessage.map(macMessageText) ?? "No messages"]
        if chat.unreadCount > 0 {
            parts.append("\(chat.unreadCount) unread")
        }
        if chat.isMarkedAsUnread {
            parts.append("Marked as unread")
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

        if chat.canBeDeletedOnlyForSelf || chat.canBeDeletedForAllUsers {
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) {
                showDeleteOptions = true
            }
        }
    }
}
