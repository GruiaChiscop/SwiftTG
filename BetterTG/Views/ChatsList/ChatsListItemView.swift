// ChatsListItemView.swift

import SwiftUI
import TDLibKit

// MARK: - ChatsListItemView

struct ChatsListItemView: View {
    // MARK: Internal

    @State var customChat: CustomChat
    
    var accessibilityDescription: String {
        customChat.accessibilityDescription
    }

    var body: some View {
        HStack(spacing: 12) {
            let chat = customChat.chat
            ProfileImageView(
                photo: chat.photo?.big,
                minithumbnail: chat.photo?.minithumbnail,
                title: chat.title,
                userId: chat.id,
                fontSize: 30,
            )
            .frame(width: 54, height: 54)
            .accessibilityHidden(true)
            
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    if let systemImage = customChat.kind.systemImage {
                        Image(systemName: systemImage)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tint)
                            .accessibilityHidden(true)
                    }

                    Text(customChat.chat.title)
                        .font(.headline)
                        .fontWeight(customChat.hasUnreadMessages ? .semibold : .regular)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    if let lastMessage = customChat.lastMessage {
                        Text(chatListTimestamp(lastMessage.date))
                            .font(.caption)
                            .foregroundStyle(
                                customChat.hasUnreadMessages
                                    ? Color.accentColor
                                    : Color(uiColor: .secondaryLabel),
                            )
                    }
                }
                
                HStack(spacing: 7) {
                    LastOrDraftMessageView(customChat: customChat)

                    Spacer(minLength: 8)

                    if customChat.isMuted {
                        Image(systemName: "speaker.slash.fill")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                    if customChat.position.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                    if customChat.unreadCount > 0 {
                        Text("\(customChat.unreadCount)")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .frame(minWidth: 24, minHeight: 22)
                            .background(.tint, in: Capsule())
                    } else if customChat.isMarkedAsUnread {
                        Circle()
                            .fill(.tint)
                            .frame(width: 10, height: 10)
                    }
                }
            }
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: Private

    private func chatListTimestamp(_ timestamp: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        if Calendar.autoupdatingCurrent.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

extension CustomChat {
    var accessibilityDescription: String {
        var parts: [String] =
            if case .privateChat = kind {
                [chat.title]
            } else {
                [kind.title, chat.title]
            }

        if unreadCount != 0 {
            parts.append("\(unreadCount) unread")
        }
        if position.isPinned {
            parts.append("Pinned")
        }
        if let draftMessage,
           case .draftMessageContentText(let content) = draftMessage.content
        {
            parts.append("Draft: \(content.text.text)")
        } else if let lastMessage {
            if lastMessage.forwardInfo != nil {
                parts.append("Forwarded")
            }
            let messageText = telegramChatListMessageDescription(lastMessage)
            if showsLastMessageSender, let lastMessageSenderName {
                parts.append("\(lastMessageSenderName): \(messageText)")
            } else {
                parts.append(messageText)
            }
            parts.append(telegramMessageDateDescription(lastMessage.date))
        }

        return parts.joined(separator: ", ")
    }
}
