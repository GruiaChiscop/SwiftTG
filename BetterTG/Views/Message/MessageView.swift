// MessageView.swift

import SwiftUI
import TDLibKit

struct MessageView: View {
    let customMessage: CustomMessage

    @Environment(ChatVM.self) var chatVM
    @State var shownAlbum: CustomMessageAlbum?
    @State var media = Media.shared
    @State var voiceNoteLocalPath: String?
    @State var showDeleteOptions = false

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let forwardedFrom = customMessage.forwardedFrom {
                ForwardedFromView(
                    name: forwardedFrom,
                    onTap: canNavigateToForwardOrigin
                        ? { chatVM.navigateToForwardOrigin(from: customMessage.message) }
                        : nil,
                )
            }

            if customMessage.replySenderName != nil, customMessage.replyToMessage != nil {
                ReplyMessageView(
                    customMessage: customMessage,
                    type: .replied,
                    onTap: { chatVM.navigateToRepliedMessage(from: customMessage.message) },
                )
            }

            if customMessage.messageDocument != nil
                || customMessage.messagePhoto != nil
                || customMessage.messageVideo != nil
                || customMessage.messageVoiceNote != nil
                || !customMessage.album.isEmpty
            {
                MessageContentView(
                    customMessage: customMessage,
                    onMediaTap: openAlbum,
                    onVoiceNoteLocalPathResolved: { voiceNoteLocalPath = $0 },
                )
            }
            
            if let formattedText = customMessage.formattedText {
                MessageTextView(formattedText: formattedText)
                    .padding(8)
                    .padding(
                        .top,
                        customMessage.replySenderName != nil && customMessage.replyToMessage != nil
                            || customMessage.forwardedFrom != nil ? -8 : 0,
                    )
            }
        }
        .background(chatVM.highlightedMessageId == customMessage.id ? .white.opacity(0.5) : .gray6)
        .clipShape(.rect(cornerRadius: 20))
        .overlay(alignment: .bottomTrailing) {
            HStack(spacing: 3) {
                if let editStatus = telegramMessageEditStatus(customMessage.message) {
                    Text(editStatus)
                }
                Text(chatVM.dateFormatter.string(from: customMessage.date))
            }
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
            if hasNavigableReply {
                $0.accessibilityAction(named: "Go to Replied Message") {
                    chatVM.navigateToRepliedMessage(from: customMessage.message)
                }
            }
        }
        .modify {
            if let forwardedFrom = customMessage.forwardedFrom, canNavigateToForwardOrigin {
                $0.accessibilityAction(named: "Go to \(forwardedFrom)") {
                    chatVM.navigateToForwardOrigin(from: customMessage.message)
                }
            }
        }
        .modify {
            if customMessage.messagePhoto != nil
                || customMessage.messageVideo != nil
                || !customMessage.album.isEmpty
            {
                $0.accessibilityAction(named: mediaAccessibilityActionName) {
                    openAlbum(albumMessage: nil)
                }
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

    private var mediaAccessibilityActionName: String {
        let containsPhoto = customMessage.messagePhoto != nil
            || customMessage.album.contains { if case .messagePhoto = $0.content { true } else { false } }
        let containsVideo = customMessage.messageVideo != nil
            || customMessage.album.contains { if case .messageVideo = $0.content { true } else { false } }
        if containsPhoto, containsVideo { return "Open Media" }
        return containsVideo ? "Play Video" : "Open Photo"
    }

    var accessibilityDescription: String {
        var prefix = ""

        if let forwardedFrom = customMessage.forwardedFrom {
            prefix += "Forwarded from \(forwardedFrom). "
        }
        let sender = customMessage.message.isOutgoing ? "You" : (customMessage.senderUser?.firstName ?? "Unknown")
        var parts = [String]()
        if case .messageReplyToMessage = customMessage.message.replyTo {
            parts.append("Replying to \(customMessage.replySenderName ?? "message")")
        }
        parts.append("\(sender): \(telegramMessageContentDescription(customMessage.message))")
        if let editStatus = telegramMessageEditStatus(customMessage.message) {
            parts.append(editStatus)
        }
        parts.append(telegramMessageDateDescription(customMessage.message.date))
        if let status = telegramMessageDeliveryStatus(
            customMessage.message,
            lastReadOutboxMessageId: chatVM.customChat.lastReadOutboxMessageId,
        ) {
            parts.append(status)
        }
        if let voiceNote = customMessage.messageVoiceNote {
            let elapsed = media.savedMediaPath == voiceNoteLocalPath ? Int(media.currentTime) : 0
            parts.append(telegramVoicePlaybackDescription(duration: voiceNote.voiceNote.duration, elapsed: elapsed))
        }
        if let quotedMessageExcerpt {
            parts.append("Quoted message: \(quotedMessageExcerpt)")
        }

        return prefix + parts.joined(separator: ", ")
    }

    func plainText(from message: Message) -> String {
        telegramMessageContentDescription(message)
    }

    private var quotedMessageExcerpt: String? {
        guard case .messageReplyToMessage(let reply) = customMessage.message.replyTo else { return nil }
        if let quote = reply.quote?.text.text, !quote.isEmpty {
            return telegramQuotedMessageExcerpt(quote)
        }
        if let replyToMessage = customMessage.replyToMessage {
            return telegramQuotedMessageExcerpt(plainText(from: replyToMessage))
        }
        if let content = reply.content {
            return telegramQuotedMessageExcerpt(telegramMessageContentDescription(content))
        }
        return nil
    }

    private var canNavigateToForwardOrigin: Bool {
        guard let origin = customMessage.message.forwardInfo?.origin else { return false }
        if case .messageOriginHiddenUser = origin { return false }
        return true
    }

    private var hasNavigableReply: Bool {
        guard case .messageReplyToMessage(let reply) = customMessage.message.replyTo else { return false }
        return reply.messageId != 0
    }
}
