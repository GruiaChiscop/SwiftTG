// ChatsListItemView.swift

import SwiftUI
import TDLibKit

// MARK: - ChatsListItemView

struct ChatsListItemView: View {
    @State var customChat: CustomChat
    
    var accessibilityDescription: String {
        customChat.accessibilityDescription
    }

    var body: some View {
        HStack {
            if customChat.position.isPinned {
                Image(systemName: "pin.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .padding(.leading, 10)
                    .accessibilityHidden(true)
            }
            
            let chat = customChat.chat
            ProfileImageView(
                photo: chat.photo?.big,
                minithumbnail: chat.photo?.minithumbnail,
                title: chat.title,
                userId: chat.id,
                fontSize: 40,
            )
            .frame(width: 64, height: 64)
            
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    if let systemImage = customChat.kind.systemImage {
                        Image(systemName: systemImage)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 16)
                            .accessibilityHidden(true)
                    }

                    Text(customChat.chat.title)
                        .font(.title2)
                        .foregroundStyle(.white)
                }
                
                LastOrDraftMessageView(customChat: customChat)
            }
            .lineLimit(1)
            
            if customChat.unreadCount != 0 {
                Spacer()
                
                Circle()
                    .fill(.gray)
                    .frame(width: 32, height: 32)
                    .overlay {
                        Text("\(customChat.unreadCount)")
                            .font(.callout)
                            .foregroundStyle(.white)
                            .minimumScaleFactor(0.5)
                    }
                    .padding(.trailing, 10)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(5)
        .background(Color.gray6)
        .clipShape(.rect(cornerRadius: 20))
        .padding(.horizontal, 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
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
            let messageText = telegramMessageContentDescription(lastMessage)
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
