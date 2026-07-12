// MessageView.swift

import SwiftUI
import TDLibKit

struct MessageView: View {
    let customMessage: CustomMessage

    @Environment(ChatVM.self) var chatVM
    @State var shownAlbum: CustomMessageAlbum?
    @State var voiceNoteLocalPath: String?
    @State var showDeleteOptions = false

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let forwardedFrom = customMessage.forwardedFrom {
                ForwardedFromView(name: forwardedFrom)
            }

            if customMessage.replyUser != nil, let replyToMessage = customMessage.replyToMessage {
                ReplyMessageView(
                    customMessage: customMessage,
                    type: .replied,
                    onTap: { chatVM.scrollTo(id: replyToMessage.id) },
                )
            }

            if customMessage.messagePhoto != nil
                || customMessage.messageVoiceNote != nil
                || !customMessage.album.isEmpty
            {
                MessageContentView(
                    customMessage: customMessage,
                    onPhotoTap: openAlbum,
                    onVoiceNoteLocalPathResolved: { voiceNoteLocalPath = $0 },
                )
            }
            
            if let formattedText = customMessage.formattedText {
                MessageTextView(formattedText: formattedText)
                    .padding(8)
                    .padding(
                        .top,
                        customMessage.replyUser != nil && customMessage.replyToMessage != nil
                            || customMessage.forwardedFrom != nil ? -8 : 0,
                    )
            }
        }
        .background(chatVM.highlightedMessageId == customMessage.id ? .white.opacity(0.5) : .gray6)
        .clipShape(.rect(cornerRadius: 20))
        .overlay(alignment: .bottomTrailing) {
            Text(chatVM.dateFormatter.string(from: customMessage.date))
                .font(.system(size: 12))
                .foregroundStyle(.white)
                .padding(3)
                .background(Color.gray6)
                .clipShape(.rect(cornerRadius: 10))
                .padding(5)
                .opacity(0.5)
        }
        .customContextMenu(cornerRadius: 20, contextMenuActions)
        .sheet(item: $shownAlbum) { album in
            ChatViewAlbum(album: album.photos, selection: album.selection)
        }
        .confirmationDialog("Delete message?", isPresented: $showDeleteOptions) {
            if customMessage.properties.canBeDeletedOnlyForSelf {
                Button("Delete only for me", role: .destructive) {
                    chatVM.deleteMessage(id: customMessage.id, deleteForBoth: false)
                }
            }
            if customMessage.properties.canBeDeletedForAllUsers {
                Button("Delete for everyone", role: .destructive) {
                    chatVM.deleteMessage(id: customMessage.id, deleteForBoth: true)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        // Keep the accessibility container independent from playback controls.
        // Their icon and elapsed time update while playing and must not recreate
        // the focused VoiceOver element.
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("message-\(customMessage.id)")
        .accessibilityLabel(accessibilityDescription)
        .modify {
            if let replyToMessage = customMessage.replyToMessage {
                $0.accessibilityAction(named: "Go to Replied Message") {
                    chatVM.scrollTo(id: replyToMessage.id)
                }
            }
        }
        .modify {
            if customMessage.messagePhoto != nil || !customMessage.album.isEmpty {
                $0.accessibilityAction(named: "Open Photo") { openAlbum(albumMessage: nil) }
            }
        }
        .accessibilityActions {
            ForEach(Array(contextMenuActions.flattened().enumerated()), id: \.offset) { _, item in
                Button(item.title, action: item.action)
            }
        }
        .modify {
            if let messageVoiceNote = customMessage.messageVoiceNote {
                $0
                    .onTapGesture {
                        guard let voiceNoteLocalPath else { return }
                        Media.shared.toggle(
                            with: voiceNoteLocalPath,
                            duration: messageVoiceNote.voiceNote.duration,
                        )
                    }
                    .accessibilityHint("Double tap to play or pause")
                    .accessibilityAddTraits(.startsMediaSession)
            }
        }
    }

    func openAlbum(albumMessage: Message?) {
        if customMessage.album.isEmpty {
            shownAlbum = .init(
                photos: [customMessage.message],
                selection: customMessage.message.id,
            )
        } else if let albumMessage {
            shownAlbum = .init(photos: customMessage.album, selection: albumMessage.id)
        } else if let first = customMessage.album.first {
            shownAlbum = .init(photos: customMessage.album, selection: first.id)
        }
    }

    var accessibilityDescription: String {
        var prefix = ""

        if let forwardedFrom = customMessage.forwardedFrom {
            prefix += "Forwarded from \(forwardedFrom). "
        }
        if customMessage.replyUser != nil, let replyToMessage = customMessage.replyToMessage {
            prefix += "Replying to \(customMessage.replyUser?.firstName ?? "message"): \(plainText(from: replyToMessage)). "
        }

        let sender = customMessage.message.isOutgoing ? "You" : (customMessage.senderUser?.firstName ?? "Unknown")
        var parts = [
            "\(sender): \(plainText(from: customMessage.message))",
            chatVM.dateFormatter.string(from: customMessage.date),
        ]
        if customMessage.message.isOutgoing {
            parts.append(isSeen ? "Seen" : "Sent")
        }

        return prefix + parts.joined(separator: ", ")
    }

    var isSeen: Bool {
        customMessage.message.id <= chatVM.customChat.chat.lastReadOutboxMessageId
    }

    func plainText(from message: Message) -> String {
        switch message.content {
        case .messageText(let messageText):
            messageText.text.text
        case .messagePhoto(let messagePhoto):
            messagePhoto.caption.text.isEmpty ? "Photo" : "Photo: \(messagePhoto.caption.text)"
        case .messageVoiceNote(let messageVoiceNote):
            messageVoiceNote.caption.text.isEmpty ? "Voice message" : "Voice message: \(messageVoiceNote.caption.text)"
        case .messageUnsupported:
            "Unsupported message"
        default:
            "Message"
        }
    }
}
