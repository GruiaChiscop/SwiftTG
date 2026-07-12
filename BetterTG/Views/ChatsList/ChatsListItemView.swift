// ChatsListItemView.swift

import SwiftUI
import TDLibKit

struct ChatsListItemView: View {
    @State var customChat: CustomChat
    
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
                Text(customChat.chat.title)
                    .font(.title2)
                    .foregroundStyle(.white)
                
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

    var accessibilityDescription: String {
        var parts = [customChat.chat.title]

        if customChat.position.isPinned {
            parts.append("Pinned")
        }
        if let draftMessage = customChat.draftMessage,
           case .draftMessageContentText(let draftMessageContentText) = draftMessage.content
        {
            parts.append("Draft: \(draftMessageContentText.text.text)")
        } else if let lastMessage = customChat.lastMessage {
            if lastMessage.forwardInfo != nil {
                parts.append("Forwarded")
            }
            parts.append(plainText(from: lastMessage))
        }
        if customChat.unreadCount != 0 {
            parts.append("\(customChat.unreadCount) unread")
        }

        return parts.joined(separator: ", ")
    }

    func plainText(from message: Message) -> String {
        switch message.content {
        case .messageText(let messageText):
            messageText.text.text
        case .messagePhoto(let messagePhoto):
            messagePhoto.caption.text.isEmpty ? "Photo" : messagePhoto.caption.text
        case .messageVoiceNote(let messageVoiceNote):
            messageVoiceNote.caption.text.isEmpty ? "Voice message" : "Voice message: \(messageVoiceNote.caption.text)"
        case .messageUnsupported:
            "Unsupported message"
        default:
            "Message"
        }
    }
}
