// MacChatList.swift

import SwiftUI
import TDLibKit

struct MacChatRow: View {
    // MARK: Internal

    @Bindable var model: MacSessionModel

    let chat: ChatListItemState
    let chatList: ChatList

    var body: some View {
        HStack(spacing: 11) {
            chatAvatar

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(chat.title)
                        .font(.body)
                        .fontWeight(chat.hasUnreadMessages ? .semibold : .regular)
                        .lineLimit(1)
                    Spacer()
                    if let message = chat.lastMessage {
                        Text(
                            Date(timeIntervalSince1970: TimeInterval(message.date)),
                            format: .dateTime.hour().minute(),
                        )
                            .font(.caption)
                            .foregroundStyle(chat.hasUnreadMessages ? Color.accentColor : .secondary)
                    }
                }

                HStack(spacing: 7) {
                    Text(chat.lastMessage.map(macMessageText) ?? "No messages")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    if isMuted {
                        Image(systemName: "speaker.slash.fill")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                    if isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                    if chat.unreadCount > 0 {
                        Text("\(chat.unreadCount)")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .frame(minWidth: 24, minHeight: 20)
                            .background(Color.accentColor, in: Capsule())
                    } else if chat.isMarkedAsUnread {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 9, height: 9)
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Press Return or Space to open this chat")
        .accessibilityActions { chatAccessibilityActions }
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

    private var chatAvatar: some View {
        ZStack(alignment: .bottomTrailing) {
            Circle()
                .fill(avatarColor)
                .overlay {
                    Text(String(chat.title.prefix(1)).uppercased())
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                }

            if chat.kind != .privateChat {
                Image(systemName: chat.kind.systemImage)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(Color.accentColor, in: Circle())
                    .overlay(Circle().stroke(.background, lineWidth: 1.5))
                    .accessibilityHidden(true)
            }
        }
        .frame(width: 40, height: 40)
        .accessibilityHidden(true)
    }

    private var avatarColor: Color {
        let palette: [Color] = [.blue, .indigo, .purple, .pink, .orange, .teal]
        return palette[Int(chat.chatId.magnitude % UInt64(palette.count))]
    }

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

    /// Actions common to the context menu and VoiceOver's accessibility actions; kept as one list
    /// so the two presentations (menu buttons with icons vs. plain accessibility actions) can't
    /// drift, mirroring the pattern in `MacMessageRow`'s `rowActions`.
    private enum MacChatRowAction {
        case button(title: String, systemImage: String, role: ButtonRole? = nil, action: () -> Void)
        case divider
    }

    private var rowActions: [MacChatRowAction] {
        let policy = chat.actionPolicy
        var items: [MacChatRowAction] = [
            .button(
                title: chat.hasUnreadMessages ? "Mark as Read" : "Mark as Unread",
                systemImage: chat.hasUnreadMessages ? "envelope.open" : "envelope.badge",
            ) { model.toggleRead(for: chat) },
            .button(
                title: isArchived ? "Unarchive" : "Archive",
                systemImage: isArchived ? "tray.and.arrow.up" : "archivebox",
            ) { model.toggleArchived(chat) },
            .button(
                title: isPinned ? "Unpin" : "Pin",
                systemImage: isPinned ? "pin.slash.fill" : "pin.fill",
            ) { model.togglePinned(for: chat, in: chatList) },
            .button(
                title: isMuted ? "Unmute" : "Mute",
                systemImage: isMuted ? "speaker.wave.2" : "speaker.slash",
            ) {
                if isMuted {
                    model.setMuteDuration(0, for: chat)
                } else {
                    showMuteOptions = true
                }
            },
        ]
        if policy.canClearHistory || policy.canLeave || policy.canDeleteChat {
            items.append(.divider)
        }
        if policy.canClearHistory {
            items.append(.button(title: "Clear History", systemImage: "eraser", role: .destructive) {
                showClearHistoryOptions = true
            })
        }
        if let leaveTitle = policy.leaveActionTitle {
            items.append(.button(
                title: leaveTitle,
                systemImage: "rectangle.portrait.and.arrow.right",
                role: .destructive,
            ) { showLeaveConfirmation = true })
        } else if policy.canDeleteChat {
            items.append(.button(title: policy.deleteActionTitle, systemImage: "trash", role: .destructive) {
                showDeleteOptions = true
            })
        }
        return items
    }

    @ViewBuilder private var chatActions: some View {
        ForEach(Array(rowActions.enumerated()), id: \.offset) { _, item in
            switch item {
            case .button(let title, let systemImage, let role, let action):
                Button(title, systemImage: systemImage, role: role, action: action)
            case .divider:
                Divider()
            }
        }
    }

    /// SwiftUI presents .accessibilityActions in reverse declaration order, so `rowActions` is
    /// reversed here (dividers dropped) to have VoiceOver announce them in the intended order:
    /// Mark as Read -> Archive -> Pin -> Mute -> Clear History -> Leave/Delete.
    @ViewBuilder private var chatAccessibilityActions: some View {
        let buttonItems = rowActions.reversed().compactMap { item -> (title: String, action: () -> Void)? in
            guard case .button(let title, _, _, let action) = item else { return nil }
            return (title, action)
        }
        ForEach(Array(buttonItems.enumerated()), id: \.offset) { _, item in
            Button(item.title, action: item.action)
        }
    }
}
