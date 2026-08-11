// LastOrDraftMessageView.swift

import SwiftUI
import TDLibKit

// MARK: - LastOrDraftMessageView

struct LastOrDraftMessageView: View {
    @State var customChat: CustomChat
    
    var body: some View {
        ZStack {
            if let draftMessage = customChat.draftMessage {
                DraftMessageView(draftMessage: draftMessage)
            } else if let lastMessage = customChat.lastMessage {
                HStack(spacing: 3) {
                    if customChat.showsLastMessageSender,
                       let senderName = customChat.lastMessageSenderName
                    {
                        Text("\(senderName):")
                            .foregroundStyle(.tint)
                    }

                    if lastMessage.forwardInfo != nil {
                        Image(systemName: "arrowshape.turn.up.right.fill")
                            .accessibilityHidden(true)
                    }
                    
                    LastMesssageView(lastMessage: lastMessage)
                }
            }
        }
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .allowsHitTesting(false)
    }
}

// MARK: - DraftMessageView

private struct DraftMessageView: View {
    let draftMessage: DraftMessage
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            Text("Draft: ")
                .foregroundStyle(.red)
            
            if draftMessage.replyTo != nil {
                Text("reply ")
                    .foregroundStyle(.primary)
            }
            
            if case .draftMessageContentText(let draftMessageContentText) = draftMessage.content {
                Text(getAttributedString(from: draftMessageContentText.text, .gray))
            }
        }
    }
}

// MARK: - LastMesssageView

private struct LastMesssageView: View {
    // MARK: Internal

    let lastMessage: Message
    
    var body: some View {
        if lastMessage.mediaAlbumId != 0 {
            albumPreview
        } else {
            messagePreview
        }
    }

    // MARK: Private

    @ViewBuilder private var albumPreview: some View {
        switch lastMessage.content {
        case .messagePhoto(let messagePhoto):
            HStack(alignment: .center, spacing: 3) {
                TdImage(photo: messagePhoto.photo, size: .sBox, contentMode: .fit)
                    .frame(width: 20, height: 20)

                if messagePhoto.caption.text.isEmpty {
                    Text("Album")
                } else {
                    Text(getAttributedString(from: messagePhoto.caption, .gray))
                }
            }
        case .messageVideo(let messageVideo):
            HStack(alignment: .center, spacing: 3) {
                TdVideoThumbnail(messageVideo: messageVideo, contentMode: .fit)
                    .frame(width: 20, height: 20)

                if messageVideo.caption.text.isEmpty {
                    Text("Album")
                } else {
                    Text(getAttributedString(from: messageVideo.caption, .gray))
                }
            }
        default:
            Text(telegramChatListMessageDescription(lastMessage))
        }
    }

    @ViewBuilder private var messagePreview: some View {
        switch lastMessage.content {
        case .messagePhoto(let messagePhoto):
            HStack(alignment: .center, spacing: 3) {
                TdImage(photo: messagePhoto.photo, size: .sBox, contentMode: .fit)
                    .frame(width: 20, height: 20)
                    
                if messagePhoto.caption.text.isEmpty {
                    Text("Photo")
                } else {
                    Text(getAttributedString(from: messagePhoto.caption, .gray))
                }
            }
        case .messageVideo(let messageVideo):
            HStack(alignment: .center, spacing: 3) {
                TdVideoThumbnail(messageVideo: messageVideo, contentMode: .fit)
                    .frame(width: 20, height: 20)

                if messageVideo.caption.text.isEmpty {
                    Text("Video")
                } else {
                    Text(getAttributedString(from: messageVideo.caption, .gray))
                }
            }
        case .messageVideoNote:
            Label("Video message", systemImage: "video.circle")
        case .messageVoiceNote(let messageVoiceNote):
            HStack(alignment: .bottom, spacing: 0) {
                Text("Voice")
                    .foregroundStyle(.primary)
                    
                if !messageVoiceNote.caption.text.isEmpty {
                    Text(": ")
                        .foregroundStyle(.primary)
                        
                    Text(getAttributedString(from: messageVoiceNote.caption, .gray))
                }
            }
        case .messageAudio(let messageAudio):
            Text(telegramAudioDescription(messageAudio))
        case .messageDocument(let messageDocument):
            if messageDocument.caption.text.isEmpty {
                Text("File: \(messageDocument.document.fileName)")
            } else {
                Text(getAttributedString(from: messageDocument.caption, .gray))
            }
        case .messageText(let messageText):
            Text(getAttributedString(from: messageText.text, .gray))
        case .messagePoll(let messagePoll):
            Text("\(messagePoll.poll.type.isQuiz ? "Quiz" : "Poll"): \(messagePoll.poll.question.text)")
        default:
            Text(telegramMessageContentDescription(lastMessage))
        }
    }
}
