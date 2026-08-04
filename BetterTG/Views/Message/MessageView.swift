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
    @State var isSavingDocument = false
    @State var isAddingContact = false
    @State var documentTransferStatus: String?
    @State var documentDownloadIsPaused = false
    @State var documentDownloadCancellationTask: Task<Void, Never>?

    var accessibilityDescription: String {
        var prefix = ""

        if let forwardedFrom = customMessage.forwardedFrom {
            prefix += "Forwarded from \(forwardedFrom). "
        }
        var parts = [String]()
        if case .messageReplyToMessage = customMessage.message.replyTo {
            parts.append("Replying to \(customMessage.replySenderName ?? "message")")
        }
        let translatedText = customMessage.showsTranslation ? customMessage.translatedText?.text : nil
        if let serviceMessageText = customMessage.serviceMessageText {
            parts.append(serviceMessageText)
        } else {
            let sender = customMessage.message.isOutgoing ? "You" : channelOrGroupAwareSenderName
            if customMessage.album.isEmpty {
                let content = translatedText?.isEmpty == false
                    ? translatedText!
                    : telegramMessageContentDescription(customMessage.message)
                parts.append("\(sender): \(content)")
            } else {
                let albumDescription = telegramMediaAlbumAccessibilityDescription(
                    itemCount: customMessage.album.count,
                )
                parts.append("\(sender): \(albumDescription)")
                let caption = translatedText?.isEmpty == false ? translatedText : customMessage.formattedText?.text
                if let caption, !caption.isEmpty {
                    parts.append(caption)
                }
            }
        }
        if let editStatus = telegramMessageEditStatus(customMessage.message) {
            parts.append(editStatus)
        }
        if translatedText?.isEmpty == false {
            parts.append("Translated")
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

            VStack(alignment: .trailing, spacing: 1) {
                VStack(alignment: .leading, spacing: 1) {
                    if showsVisualSenderName, let visualSenderName {
                        Text(visualSenderName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tint)
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                            .padding(.top, 6)
                            .accessibilityHidden(true)
                    }

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

                    if let messagePoll = customMessage.messagePoll {
                        TelegramPollView(
                            content: messagePoll,
                            message: customMessage.message,
                            service: chatVM.service,
                        ) {
                            Text(messagePoll.poll.question.text)
                                .accessibilityIdentifier("message-\(customMessage.id)")
                                .accessibilityLabel(pollAccessibilityContextDescription)
                                .accessibilityActions {
                                    messageAccessibilityActions
                                }
                        }
                    } else if let messageChecklist = customMessage.messageChecklist {
                        TelegramChecklistView(
                            content: messageChecklist,
                            message: customMessage.message,
                            canMarkTasksAsDone: customMessage.properties.canMarkTasksAsDone,
                            service: chatVM.service,
                        ) {
                            Text(messageChecklist.list.title.text)
                                .accessibilityIdentifier("message-\(customMessage.id)")
                                .accessibilityLabel(checklistAccessibilityContextDescription)
                                .accessibilityActions {
                                    messageAccessibilityActions
                                }
                        }
                    } else if customMessage.messageDocument != nil
                        || customMessage.messagePhoto != nil
                        || customMessage.messageVideo != nil
                        || customMessage.messageVoiceNote != nil
                        || customMessage.messageAudio != nil
                        || customMessage.messageSticker != nil
                        || customMessage.messageContact != nil
                        || !customMessage.album.isEmpty
                    {
                        MessageContentView(
                            customMessage: customMessage,
                            audioPlaylist: audioPlaylist,
                            service: chatVM.service,
                            onMediaTap: openAlbum,
                            onContactTap: activateContact,
                            onVoiceNoteLocalPathResolved: { voiceNoteLocalPath = $0 },
                            onDocumentTransferStatusChange: { documentTransferStatus = $0 },
                            documentDownloadIsPaused: documentDownloadIsPaused,
                            onDocumentDownloadToggle: toggleDocumentDownload,
                        )
                    }

                    if let linkPreview, linkPreview.showAboveText {
                        TelegramLinkPreviewView(preview: linkPreview, service: chatVM.service)
                            .padding(.horizontal, 8)
                            .padding(.top, 8)
                    }

                    if let formattedText = displayedFormattedText, !formattedText.text.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            MessageTextView(
                                formattedText: formattedText,
                                trailingText: visualMessageMetadataText,
                            )
                            if customMessage.showsTranslation {
                                Text("Translated")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .accessibilityHidden(true)
                            }
                        }
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

                if !hasInlineVisualMetadata {
                    standaloneVisualMessageMetadata
                }
            }
            .background {
                if !isStickerMessage {
                    messageBubbleColor
                }
            }
            .clipShape(.rect(cornerRadius: 20))
            .contextMenu {
                messageContextMenu
            }
            .modify {
                if isPollMessage || isChecklistMessage {
                    $0
                } else {
                    messageAccessibilityElement($0)
                }
            }
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
        .alert("Delete message?", isPresented: $showDeleteOptions) {
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
        .popover(
            isPresented: $showReactionOptions,
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .bottom,
        ) {
            reactionPicker
                .presentationCompactAdaptation(.popover)
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
        visualSenderName ?? "Unknown"
    }

    private var visualSenderName: String? {
        customMessage.senderUser.map(telegramUserDisplayName)
            ?? customMessage.senderChatTitle
    }

    private var showsVisualSenderName: Bool {
        chatVM.customChat.showsMessageSender
            && !customMessage.message.isOutgoing
            && customMessage.serviceMessageText == nil
    }

    private var isStickerMessage: Bool {
        customMessage.messageSticker != nil
    }

    private var isPollMessage: Bool {
        customMessage.messagePoll != nil
    }

    private var isChecklistMessage: Bool {
        customMessage.messageChecklist != nil
    }

    private var hasInlineVisualMetadata: Bool {
        guard let formattedText = customMessage.formattedText else { return false }
        return !formattedText.text.isEmpty
    }

    private var displayedFormattedText: FormattedText? {
        customMessage.showsTranslation
            ? (customMessage.translatedText ?? customMessage.formattedText)
            : customMessage.formattedText
    }

    private var messageBubbleColor: Color {
        if chatVM.highlightedMessageId == customMessage.id {
            return Color.white.opacity(0.5)
        }
        if customMessage.serviceMessageText != nil {
            return Color.gray6.opacity(0.75)
        }
        return customMessage.message.isOutgoing
            ? Color.accentColor.opacity(0.85)
            : Color.gray6
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
        !isPollMessage && !isChecklistMessage && (!textLinks.isEmpty || separatePreviewAccessibilityLink != nil)
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

    private var pollAccessibilityContextDescription: String {
        var parts = [customMessage.message.isOutgoing ? "You" : channelOrGroupAwareSenderName]
        if let poll = customMessage.messagePoll?.poll {
            parts.append(poll.type.isQuiz ? "Quiz" : "Poll")
            parts.append(poll.question.text)
        }
        parts.append(telegramMessageDateDescription(customMessage.message.date))
        if let status = telegramMessageDeliveryStatus(
            customMessage.message,
            lastReadOutboxMessageId: chatVM.customChat.lastReadOutboxMessageId,
        ) {
            parts.append(status)
        }
        return parts.joined(separator: ", ")
    }

    private var checklistAccessibilityContextDescription: String {
        var parts = [customMessage.message.isOutgoing ? "You" : channelOrGroupAwareSenderName]
        if let messageChecklist = customMessage.messageChecklist {
            parts.append(TelegramChecklistPresentation(messageChecklist).contentDescription)
        }
        parts.append(telegramMessageDateDescription(customMessage.message.date))
        if let status = telegramMessageDeliveryStatus(
            customMessage.message,
            lastReadOutboxMessageId: chatVM.customChat.lastReadOutboxMessageId,
        ) {
            parts.append(status)
        }
        return parts.joined(separator: ", ")
    }

    private var visualMessageMetadataText: AttributedString {
        var value = " "
        if telegramMessageEditStatus(customMessage.message) != nil {
            value += "edited "
        }
        value += chatVM.dateFormatter.string(from: customMessage.date)
        if let visualDeliveryStatusGlyph {
            value += " \(visualDeliveryStatusGlyph)"
        }
        return telegramAttributedString(from: NSAttributedString(
            string: value,
            attributes: [
                .font: UIFont.systemFont(ofSize: 12),
                .foregroundColor: UIColor.white.withAlphaComponent(0.65),
            ],
        ))
    }

    private var visualDeliveryStatusGlyph: String? {
        guard customMessage.message.isOutgoing else { return nil }
        switch customMessage.message.sendingState {
        case .messageSendingStatePending:
            return "◷"
        case .messageSendingStateFailed:
            return "⚠︎"
        case nil:
            return customMessage.id <= chatVM.customChat.lastReadOutboxMessageId ? "✓✓" : "✓"
        }
    }

    private var standaloneVisualMessageMetadata: some View {
        Text(visualMessageMetadataText)
            .padding(3)
            .background(Color.gray6)
            .clipShape(.rect(cornerRadius: 10))
            .padding(.horizontal, 5)
            .padding(.bottom, 5)
            .fixedSize()
            .opacity(0.5)
            .accessibilityHidden(true)
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
                            if let destination = TelegramTextFormatting.accessibilityDestination(for: link) {
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
            .accessibilityValue(documentTransferStatus ?? "")
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
                if customMessage.messageDocument != nil, documentTransferStatus != nil {
                    $0.accessibilityAction { toggleDocumentDownload() }
                } else {
                    $0
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
            .modify {
                if customMessage.messageContact != nil {
                    $0.accessibilityAction(named: contactActionTitle) {
                        activateContact()
                    }
                } else {
                    $0
                }
            }
            .accessibilityActions {
                messageAccessibilityActions
            }
    }

    private func toggleDocumentDownload() {
        guard let fileId = customMessage.messageDocument?.document.document.id else { return }
        if documentDownloadIsPaused {
            let cancellationTask = documentDownloadCancellationTask
            documentDownloadCancellationTask = nil
            Task { @MainActor in
                await cancellationTask?.value
                documentDownloadIsPaused = false
            }
        } else {
            documentDownloadIsPaused = true
            let service = chatVM.service
            documentDownloadCancellationTask = Task {
                _ = try? await service.cancelDownloadFile(
                    fileId: fileId,
                    onlyIfPending: false,
                )
            }
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
