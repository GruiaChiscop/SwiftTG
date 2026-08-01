// MessageView.swift

import SwiftUI
import TDLibKit

struct MessageView: View {
    // MARK: Internal

    let customMessage: CustomMessage

    @Environment(ChatVM.self) var chatVM
    @State var shownAlbum: CustomMessageAlbum?
    @State var media = Media.shared
    @State var audioPlayer = TelegramAudioPlayer.shared
    @State var voiceNoteLocalPath: String?
    @State var showDeleteOptions = false
    @State var showReactionOptions = false
    @State var showReactionDetails = false

    var accessibilityDescription: String {
        var prefix = ""

        if let forwardedFrom = customMessage.forwardedFrom {
            prefix += "Forwarded from \(forwardedFrom). "
        }
        var parts = [String]()
        if case .messageReplyToMessage = customMessage.message.replyTo {
            parts.append("Replying to \(customMessage.replySenderName ?? "message")")
        }
        if let serviceMessageText = customMessage.serviceMessageText {
            parts.append(serviceMessageText)
        } else {
            let sender = customMessage.message.isOutgoing ? "You" : channelOrGroupAwareSenderName
            parts.append("\(sender): \(telegramMessageContentDescription(customMessage.message))")
        }
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
        if let messageAudio = customMessage.messageAudio {
            let elapsed = audioPlayer.currentFileId == messageAudio.audio.audio.id
                ? audioPlayer.currentTime
                : 0
            parts.append(telegramVoicePlaybackDescription(duration: messageAudio.audio.duration, elapsed: elapsed))
            if audioPlayer.currentFileId == messageAudio.audio.audio.id {
                if audioPlayer.isBuffering {
                    parts.append("Buffering")
                }
                if let playbackError = audioPlayer.playbackError {
                    parts.append(playbackError)
                }
            }
        }
        if let quotedMessageExcerpt {
            parts.append("Quoted message: \(quotedMessageExcerpt)")
        }
        return prefix + parts.joined(separator: ", ")
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 5) {
            if customMessage.message.isOutgoing, !messageReactions.isEmpty {
                reactionsButton
            }

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
                    || customMessage.messageAudio != nil
                    || !customMessage.album.isEmpty
                {
                    MessageContentView(
                        customMessage: customMessage,
                        audioPlaylist: audioPlaylist,
                        onMediaTap: openAlbum,
                        onVoiceNoteLocalPathResolved: { voiceNoteLocalPath = $0 },
                    )
                }

                if let linkPreview, linkPreview.showAboveText {
                    TelegramLinkPreviewView(preview: linkPreview, service: chatVM.service)
                        .padding(.horizontal, 8)
                        .padding(.top, 8)
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

                if let linkPreview, !linkPreview.showAboveText {
                    TelegramLinkPreviewView(preview: linkPreview, service: chatVM.service)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 8)
                }
            }
            .background(
                chatVM.highlightedMessageId == customMessage.id
                    ? .white.opacity(0.5)
                    : (customMessage.serviceMessageText == nil ? .gray6 : .gray6.opacity(0.75)),
            )
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
            .contextMenu {
                messageContextMenu
            }
            .modify { messageAccessibilityElement($0) }
            .accessibilityHidden(hasAccessibilityGroup)

            if !customMessage.message.isOutgoing, !messageReactions.isEmpty {
                reactionsButton
            }
        }
        .modify {
            if !hasAccessibilityGroup {
                $0
            } else {
                linkAccessibilityGroup($0)
            }
        }
        .sheet(item: $shownAlbum) { album in
            ChatViewAlbum(album: album.photos, selection: album.selection)
        }
        .sheet(isPresented: $showReactionDetails) {
            TelegramReactionDetailsView(
                service: chatVM.service,
                chatId: customMessage.message.chatId,
                messageId: customMessage.id,
            )
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
        .confirmationDialog("React", isPresented: $showReactionOptions) {
            ForEach(reactionChoices, id: \.self) { reaction in
                Button(telegramReactionActionTitle(reaction, existing: messageReactions)) {
                    toggleReaction(reaction)
                }
            }
            Button("Cancel", role: .cancel) {}
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

    func plainText(from message: Message) -> String {
        telegramMessageContentDescription(message)
    }

    // MARK: Private

    /// A channel post (or an anonymous "as the group" admin post) has no `User` sender at all, so
    /// falling back straight to "Unknown" there was wrong for every such message - fall back to the
    /// sender chat's own title instead, matching how macOS resolves the same case.
    private var channelOrGroupAwareSenderName: String {
        customMessage.senderUser?.firstName ?? customMessage.senderChatTitle ?? "Unknown"
    }

    private var textLinks: [TelegramTextLink] {
        guard let formattedText = customMessage.formattedText else { return [] }
        return TelegramTextFormatting.links(in: formattedText)
    }

    private var linkPreview: LinkPreview? {
        telegramMessageLinkPreview(customMessage.message)
    }

    private var separatePreviewAccessibilityLink: TelegramLinkPreviewPresentation? {
        guard let linkPreview else { return nil }
        let presentation = TelegramLinkPreviewPresentation(linkPreview)
        guard let destination = presentation.url,
              !textLinks.contains(where: { telegramURLsReferToSameResource($0.url, destination) })
        else { return nil }
        return presentation
    }

    private var hasAccessibilityGroup: Bool {
        !textLinks.isEmpty || separatePreviewAccessibilityLink != nil
    }

    private var audioPlaylist: [Audio] {
        chatVM.audioPlaylist
    }

    private var mediaAccessibilityActionName: String {
        let containsPhoto = customMessage.messagePhoto != nil
            || customMessage.album.contains {
                if case .messagePhoto = $0.content {
                    true
                } else {
                    false
                }
            }
        let containsVideo = customMessage.messageVideo != nil
            || customMessage.album.contains {
                if case .messageVideo = $0.content {
                    true
                } else {
                    false
                }
            }
        if containsPhoto, containsVideo {
            return "Open Media"
        }
        return containsVideo ? "Play Video" : "Open Photo"
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
        if case .messageOriginHiddenUser = origin {
            return false
        }
        return true
    }

    private var hasNavigableReply: Bool {
        guard case .messageReplyToMessage(let reply) = customMessage.message.replyTo else { return false }
        return reply.messageId != 0
    }

    private var reactionsButton: some View {
        TelegramMessageReactionsView(reactions: messageReactions) {
            showReactionDetails = true
        }
        .accessibilityHidden(hasAccessibilityGroup)
    }

    private func linkAccessibilityGroup(_ content: some View) -> some View {
        content
            .accessibilityElement(children: .contain)
            .accessibilityChildren {
                messageAccessibilityElement(Text(accessibilityDescription))
                ForEach(textLinks) { link in
                    Link(link.displayedText, destination: link.url)
                        .accessibilityRemoveTraits(.isButton)
                        .accessibilityAddTraits(.isLink)
                        .modify {
                            if let destination = linkAccessibilityDestination(link) {
                                $0.accessibilityValue(destination)
                            } else {
                                $0
                            }
                        }
                }
                if let preview = separatePreviewAccessibilityLink, let destination = preview.url {
                    Link(preview.accessibilityLinkLabel, destination: destination)
                        .accessibilityRemoveTraits(.isButton)
                        .accessibilityAddTraits(.isLink)
                }
                if !messageReactions.isEmpty {
                    Button("Reactions") { showReactionDetails = true }
                        .accessibilityValue(telegramReactionDescription(messageReactions) ?? "")
                }
            }
    }

    private func messageAccessibilityElement(_ content: some View) -> some View {
        // Keep the message stable while playback controls and elapsed time update.
        content
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("message-\(customMessage.id)")
            .accessibilityLabel(accessibilityDescription)
            .modify {
                if let messageVoiceNote = customMessage.messageVoiceNote {
                    $0
                        .onTapGesture { toggleVoiceMessage(messageVoiceNote) }
                        .accessibilityHint("Double tap to play or pause")
                        .accessibilityAddTraits(.startsMediaSession)
                }
            }
            .modify {
                if let messageAudio = customMessage.messageAudio {
                    $0
                        .onTapGesture { toggleAudioMessage(messageAudio) }
                        .accessibilityHint("Double tap to play or pause")
                        .accessibilityAddTraits(.startsMediaSession)
                }
            }
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
                messageAccessibilityActions
            }
    }

    private func linkAccessibilityDestination(_ link: TelegramTextLink) -> String? {
        guard let scheme = link.url.scheme?.lowercased() else { return nil }
        switch scheme {
        case "http", "https":
            guard let host = link.url.host,
                  !link.displayedText.localizedCaseInsensitiveContains(host)
            else { return nil }
            return host
        default:
            return nil
        }
    }

    private func toggleAudioMessage(_ messageAudio: MessageAudio) {
        Media.shared.stop()
        audioPlayer.toggle(
            audio: messageAudio.audio,
            service: chatVM.service,
            playlist: audioPlaylist,
        )
    }

    private func toggleVoiceMessage(_ messageVoiceNote: MessageVoiceNote) {
        Task { @MainActor in
            if let resolvedPath = await chatVM.toggleVoiceMessage(
                messageVoiceNote,
                knownLocalPath: voiceNoteLocalPath,
            ) {
                voiceNoteLocalPath = resolvedPath
            }
        }
    }
}
