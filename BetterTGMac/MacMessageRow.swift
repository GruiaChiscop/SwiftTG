// MacMessageRow.swift

import AppKit
import AVKit
import SwiftUI
import TDLibKit

// MARK: - MacMessageRow

struct MacMessageRow: View {
    // MARK: Internal

    @Bindable var model: MacSessionModel

    let message: Message
    let albumMessages: [Message]
    let lastReadOutboxMessageId: Int64

    var body: some View {
        HStack {
            if isServiceMessage || message.isOutgoing {
                Spacer(minLength: 80)
            }
            HStack(alignment: .bottom, spacing: 5) {
                if message.isOutgoing, !messageReactions.isEmpty {
                    reactionsButton
                }
                VStack(alignment: .leading, spacing: 4) {
                    if let forwardedFrom = model.messageForwardedFrom[message.id] {
                        if canNavigateToForwardOrigin {
                            Button {
                                model.navigateToForwardOrigin(from: message)
                            } label: {
                                Text("Forwarded from \(forwardedFrom)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Text("Forwarded from \(forwardedFrom)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let replyContext = model.messageReplyContexts[message.id] {
                        Button {
                            model.navigateToRepliedMessage(from: message)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Replying to \(replyContext.senderName)")
                                    .font(.caption.weight(.semibold))
                                Text(replyContext.quotedText)
                                    .lineLimit(2)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Go to Replied Message")
                    }
                    if isVisualAlbum {
                        if albumCaptionShowsAbove, let albumCaption {
                            MacFormattedTextView(formattedText: albumCaption)
                        }
                        MacMediaAlbumView(model: model, messages: albumMessages) { albumMessage in
                            selectedAlbumMessage = albumMessage
                        }
                        if !albumCaptionShowsAbove, let albumCaption {
                            MacFormattedTextView(formattedText: albumCaption)
                        }
                    } else if case .messageDocument(let content) = message.content {
                        MacDocumentMessageContent(
                            content: content,
                            isDownloaded: documentPath != nil,
                            isLoading: isLoadingDocument,
                            onOpen: openDocument,
                        )
                    } else if case .messagePhoto(let content) = message.content {
                        MacPhotoMessageContent(
                            content: content,
                            image: photoImage,
                            onOpen: { showPhotoPreview = true },
                        )
                    } else if case .messageVideo(let content) = message.content {
                        MacVideoMessageContent(
                            content: content,
                            thumbnail: videoThumbnailImage,
                            onOpen: { showVideoPreview = true },
                        )
                    } else if case .messageVoiceNote(let content) = message.content {
                        MacVoiceMessageContent(
                            caption: content.caption,
                            voiceNote: content.voiceNote,
                            path: voicePath,
                            player: player,
                        )
                    } else if case .messageAudio(let content) = message.content {
                        MacAudioMessageContent(
                            audio: content.audio,
                            caption: content.caption,
                            playlist: audioPlaylist,
                            service: model.service,
                            player: audioPlayer,
                        )
                    } else if case .messageSticker(let content) = message.content {
                        MacStickerView(
                            model: model,
                            content: content,
                            playsAnimation: message.sendingState == nil,
                        )
                    } else if case .messagePoll(let content) = message.content {
                        TelegramPollView(content: content, message: message, service: model.service) {
                            Text(content.poll.question.text)
                                .accessibilityIdentifier("message-\(message.id)")
                                .accessibilityLabel(pollAccessibilityContextDescription)
                                .accessibilityActions { messageAccessibilityActions }
                        }
                    } else if case .messageText(let content) = message.content {
                        if let linkPreview = content.linkPreview, linkPreview.showAboveText {
                            MacLinkPreviewView(model: model, preview: linkPreview)
                        }
                        if !content.text.text.isEmpty {
                            MacFormattedTextView(formattedText: content.text)
                        }
                        if let linkPreview = content.linkPreview, !linkPreview.showAboveText {
                            MacLinkPreviewView(model: model, preview: linkPreview)
                        }
                    } else if let formattedText = telegramMessageFormattedText(message) {
                        MacFormattedTextView(formattedText: formattedText)
                    } else {
                        Text(displayedMessageText)
                            .textSelection(.enabled)
                    }
                    HStack(spacing: 5) {
                        if let editStatus = telegramMessageEditStatus(message) {
                            Text(editStatus)
                        }
                        Text(Date(timeIntervalSince1970: TimeInterval(message.date)), format: .dateTime.hour().minute())
                        if let status = telegramMessageDeliveryStatus(
                            message,
                            lastReadOutboxMessageId: lastReadOutboxMessageId,
                        ) {
                            Text(status)
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background {
                    if !isStickerMessage {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(
                                isServiceMessage
                                    ? Color.secondary.opacity(0.12)
                                    : (message.isOutgoing
                                        ? Color.accentColor.opacity(0.18)
                                        : Color.secondary.opacity(0.12)),
                            )
                    }
                }
                .macModified {
                    if isPollMessage {
                        $0
                    } else if isVisualAlbum {
                        albumAccessibilityRepresentation($0)
                    } else {
                        messageAccessibilityElement($0)
                    }
                }
                .accessibilityHidden(hasAccessibilityGroup)
                .contextMenu { messageActions }
                if !message.isOutgoing, !messageReactions.isEmpty {
                    reactionsButton
                }
            }
            .macModified {
                if hasAccessibilityGroup {
                    linkAccessibilityGroup($0)
                } else {
                    $0
                }
            }
            if isServiceMessage || !message.isOutgoing {
                Spacer(minLength: 80)
            }
        }
        .contentShape(Rectangle())
        .contextMenu { messageActions }
        .task(id: presentationTaskID) {
            guard let voiceFileId else { return }
            voicePath = await model.localVoiceNotePath(fileId: voiceFileId)
        }
        .task(id: presentationTaskID) {
            guard !isVisualAlbum,
                  let photoFileId,
                  let path = await model.localPhotoPath(fileId: photoFileId)
            else {
                photoPath = nil
                photoImage = nil
                return
            }
            photoPath = path
            photoImage = await Self.decodedImage(atPath: path)
        }
        .task(id: presentationTaskID) {
            guard !isVisualAlbum,
                  let videoThumbnailFileId,
                  let path = await model.localPhotoPath(fileId: videoThumbnailFileId)
            else {
                videoThumbnailImage = nil
                return
            }
            videoThumbnailImage = await Self.decodedImage(atPath: path)
        }
        .task(id: presentationTaskID) {
            await model.loadCapabilities(for: message)
        }
        .task(id: presentationTaskID) {
            await model.loadReplyContext(for: message)
        }
        .task(id: presentationTaskID) {
            await model.loadForwardedFrom(for: message)
        }
        .task(id: presentationTaskID) {
            await model.loadSenderName(for: message)
        }
        .task(id: presentationTaskID) {
            await model.loadServiceDescription(for: message)
        }
        .confirmationDialog("Delete message?", isPresented: $showDeleteOptions) {
            if capabilities?.properties.canBeDeletedOnlyForSelf == true {
                Button("Delete only for me", role: .destructive) {
                    model.delete(message, forEveryone: false)
                }
            }
            if capabilities?.properties.canBeDeletedForAllUsers == true {
                Button("Delete for everyone", role: .destructive) {
                    model.delete(message, forEveryone: true)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("React", isPresented: $showReactionOptions) {
            ForEach(reactionChoices, id: \.self) { reaction in
                Button(telegramReactionActionTitle(reaction, existing: messageReactions)) {
                    model.toggleReaction(reaction, on: message)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showPhotoPreview) {
            if case .messagePhoto(let content) = message.content,
               let photoImage,
               let photoPath
            {
                MacPhotoPreview(
                    image: photoImage,
                    caption: content.caption.text,
                    fileURL: URL(filePath: photoPath),
                )
            }
        }
        .sheet(isPresented: $showVideoPreview) {
            if case .messageVideo(let content) = message.content {
                MacVideoPreview(
                    model: model,
                    fileId: content.video.video.id,
                    caption: content.caption.text,
                    duration: content.video.duration,
                    startTimestamp: content.startTimestamp,
                )
            }
        }
        .sheet(item: $selectedAlbumMessage) { albumMessage in
            MacAlbumMediaPreview(model: model, message: albumMessage)
        }
        .sheet(isPresented: $showReactionDetails) {
            TelegramReactionDetailsView(
                service: model.service,
                chatId: message.chatId,
                messageId: message.id,
            )
        }
        .sheet(isPresented: $showForwardPicker) {
            MacForwardChatPicker(model: model, message: message)
        }
    }

    // MARK: Private

    /// Actions common to the context menu and VoiceOver's accessibility actions; kept as one list so
    /// the two presentations (menu buttons with icons vs. plain accessibility actions) can't drift.
    /// "React" and "Delete" are still special-cased below since each renders differently per surface
    /// (a reactions submenu vs. a single toggle; a destructive button with a leading divider vs. plain).
    private enum MacRowAction {
        case button(title: String, systemImage: String, action: () -> Void)
        case reactions
    }

    @State private var player = MacVoicePlayer.shared
    @State private var audioPlayer = TelegramAudioPlayer.shared
    @State private var documentPath: String?
    @State private var isLoadingDocument = false
    @State private var photoImage: NSImage?
    @State private var photoPath: String?
    @State private var videoThumbnailImage: NSImage?
    @State private var voicePath: String?
    @State private var showDeleteOptions = false
    @State private var showReactionOptions = false
    @State private var showReactionDetails = false
    @State private var showPhotoPreview = false
    @State private var showVideoPreview = false
    @State private var showForwardPicker = false
    @State private var selectedAlbumMessage: Message?

    private var capabilities: MacMessageCapabilities? {
        model.messageCapabilities[message.id]
    }

    private var audioPlaylist: [Audio] {
        model.messages.orderedMessageIds.compactMap { messageId in
            guard let queuedMessage = model.messages.messages[messageId],
                  case .messageAudio(let content) = queuedMessage.content
            else { return nil }
            return content.audio
        }
    }

    private var presentationTaskID: String {
        "\(message.id):\(message.editDate)"
    }

    private var isVisualAlbum: Bool {
        !albumMessages.isEmpty
    }

    private var albumCaption: FormattedText? {
        albumMessages.lazy.compactMap(telegramMessageFormattedText).first
    }

    private var albumCaptionShowsAbove: Bool {
        guard let captionMessage = albumMessages.first(where: { telegramMessageFormattedText($0) != nil }) else {
            return false
        }
        switch captionMessage.content {
        case .messagePhoto(let content): return content.showCaptionAboveMedia
        case .messageVideo(let content): return content.showCaptionAboveMedia
        default: return false
        }
    }

    private var canNavigateToForwardOrigin: Bool {
        guard let origin = message.forwardInfo?.origin else { return false }
        if case .messageOriginHiddenUser = origin {
            return false
        }
        return true
    }

    private var canCopy: Bool {
        capabilities?.properties.canBeCopied == true && copyableMessageText(message) != nil
    }

    private var canDelete: Bool {
        capabilities?.properties.canBeDeletedOnlyForSelf == true
            || capabilities?.properties.canBeDeletedForAllUsers == true
    }

    private var voiceFileId: Int? {
        guard case .messageVoiceNote(let content) = message.content else { return nil }
        return content.voiceNote.voice.id
    }

    private var audioFileId: Int? {
        guard case .messageAudio(let content) = message.content else { return nil }
        return content.audio.audio.id
    }

    private var documentFileId: Int? {
        guard case .messageDocument(let content) = message.content else { return nil }
        return content.document.document.id
    }

    private var activationHint: String {
        if voiceFileId != nil || audioFileId != nil {
            return "Press to play or pause"
        }
        if documentFileId != nil {
            return "Press to open document"
        }
        if photoFileId != nil {
            return "Press to open photo"
        }
        if videoFileId != nil {
            return "Press to play video"
        }
        return ""
    }

    private var hasDefaultActivation: Bool {
        voiceFileId != nil || audioFileId != nil || documentFileId != nil || photoFileId != nil || videoFileId != nil
    }

    private var photoFileId: Int? {
        guard case .messagePhoto(let content) = message.content else { return nil }
        return content.photo
            .sizes
            .max {
                $0.width * $0.height < $1.width * $1.height
            }?.photo
            .id
    }

    private var videoFileId: Int? {
        guard case .messageVideo(let content) = message.content else { return nil }
        return content.video.video.id
    }

    private var videoThumbnailFileId: Int? {
        guard case .messageVideo(let content) = message.content else { return nil }
        if let cover = content.cover {
            return cover.sizes
                .max {
                    $0.width * $0.height < $1.width * $1.height
                }?.photo
                .id
        }
        return content.video.thumbnail?.file.id
    }

    private var accessibilityDescription: String {
        macMessageAccessibilityDescription(
            model: model,
            message: message,
            lastReadOutboxMessageId: lastReadOutboxMessageId,
            voicePlayer: player,
            audioPlayer: audioPlayer,
        )
    }

    private var messageReactions: [MessageReaction] {
        message.interactionInfo?.reactions?.reactions ?? []
    }

    private var reactionChoices: [ReactionType] {
        telegramReactionChoices(
            existing: messageReactions,
            available: model.messageAvailableReactions[message.id] ?? [],
        )
    }

    private var displayedMessageText: String {
        model.messageServiceDescriptions[message.id] ?? telegramMessageContentDescription(message)
    }

    private var isServiceMessage: Bool {
        TelegramServiceMessage.isServiceMessage(message.content)
    }

    private var isStickerMessage: Bool {
        if case .messageSticker = message.content {
            true
        } else {
            false
        }
    }

    private var isPollMessage: Bool {
        if case .messagePoll = message.content {
            true
        } else {
            false
        }
    }

    private var messageLinks: [TelegramTextLink] {
        guard let formattedText = isVisualAlbum ? albumCaption : telegramMessageFormattedText(message) else {
            return []
        }
        return TelegramTextFormatting.links(in: formattedText)
    }

    private var separatePreviewAccessibilityLink: TelegramLinkPreviewPresentation? {
        guard let linkPreview = telegramMessageLinkPreview(message) else { return nil }
        let presentation = TelegramLinkPreviewPresentation(linkPreview)
        guard let destination = presentation.url,
              !messageLinks.contains(where: { telegramURLsReferToSameResource($0.url, destination) })
        else { return nil }
        return presentation
    }

    private var hasAccessibilityGroup: Bool {
        !isPollMessage &&
            (!messageReactions.isEmpty || !messageLinks.isEmpty || separatePreviewAccessibilityLink != nil)
    }

    private var rowActions: [MacRowAction] {
        var items = [MacRowAction]()
        if capabilities?.properties.canBeReplied == true {
            items.append(.button(title: "Reply", systemImage: "arrowshape.turn.up.left") {
                model.beginReply(to: message)
            })
        }
        if capabilities?.properties.canBeForwarded == true {
            items.append(.button(title: "Forward", systemImage: "arrowshape.turn.up.right") {
                showForwardPicker = true
            })
        }
        if model.messageReplyContexts[message.id]?.messageId != nil {
            items.append(.button(title: "Go to Replied Message", systemImage: "arrow.up.left") {
                model.navigateToRepliedMessage(from: message)
            })
        }
        if let forwardedFrom = model.messageForwardedFrom[message.id], canNavigateToForwardOrigin {
            items.append(.button(title: "Go to \(forwardedFrom)", systemImage: "arrow.up.right.square") {
                model.navigateToForwardOrigin(from: message)
            })
        }
        if !reactionChoices.isEmpty {
            items.append(.reactions)
        }
        if canCopy {
            items.append(.button(title: "Copy", systemImage: "doc.on.doc") { copyMessageText() })
        }
        if !isVisualAlbum, photoImage != nil {
            items.append(.button(title: "Open Photo", systemImage: "photo") { showPhotoPreview = true })
        }
        if !isVisualAlbum, videoFileId != nil {
            items.append(.button(title: "Play Video", systemImage: "play.rectangle") { showVideoPreview = true })
        }
        if capabilities?.properties.canBeEdited == true, editableMessageText(message) != nil {
            items.append(.button(title: "Edit", systemImage: "square.and.pencil") { model.beginEditing(message) })
        }
        if capabilities?.properties.canBePinned == true {
            items.append(.button(
                title: message.isPinned ? "Unpin" : "Pin",
                systemImage: message.isPinned ? "pin.slash" : "pin",
            ) { model.togglePin(for: message) })
        }
        return items
    }

    private var pollAccessibilityContextDescription: String {
        var parts = [message.isOutgoing ? "You" : model.cachedSenderName(for: message) ?? "Unknown sender"]
        if case .messagePoll(let content) = message.content {
            parts.append(content.poll.type.isQuiz ? "Quiz" : "Poll")
            parts.append(content.poll.question.text)
        }
        parts.append(telegramMessageDateDescription(message.date))
        if let status = telegramMessageDeliveryStatus(
            message,
            lastReadOutboxMessageId: lastReadOutboxMessageId,
        ) {
            parts.append(status)
        }
        return parts.joined(separator: ", ")
    }

    private var albumAccessibilityDescription: String {
        var parts = [message.isOutgoing ? "You" : model.cachedSenderName(for: message) ?? "Unknown sender"]
        parts.append(telegramMediaAlbumAccessibilityDescription(itemCount: albumMessages.count))
        if let albumCaption {
            parts.append(albumCaption.text)
        }
        parts.append(telegramMessageDateDescription(message.date))
        if let status = telegramMessageDeliveryStatus(
            message,
            lastReadOutboxMessageId: lastReadOutboxMessageId,
        ) {
            parts.append(status)
        }
        return parts.joined(separator: ", ")
    }

    @ViewBuilder private var messageActions: some View {
        ForEach(Array(rowActions.enumerated()), id: \.offset) { _, item in
            switch item {
            case .button(let title, let systemImage, let action):
                Button(title, systemImage: systemImage, action: action)
            case .reactions:
                Menu("React", systemImage: "face.smiling") {
                    ForEach(reactionChoices, id: \.self) { reaction in
                        Button(telegramReactionActionTitle(reaction, existing: messageReactions)) {
                            model.toggleReaction(reaction, on: message)
                        }
                    }
                }
            }
        }
        if canDelete {
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) {
                showDeleteOptions = true
            }
        }
    }

    @ViewBuilder private var messageAccessibilityActions: some View {
        // SwiftUI presents .accessibilityActions in reverse declaration order, so the combined
        // list (row actions, then Delete) is reversed as a whole here to have VoiceOver announce
        // them in the intended order, ending with Delete.
        let items = rowActions + (canDelete
            ? [.button(title: "Delete", systemImage: "trash") { showDeleteOptions = true }]
            : [])
        ForEach(Array(items.reversed().enumerated()), id: \.offset) { _, item in
            switch item {
            case .button(let title, _, let action):
                Button(title, action: action)
            case .reactions:
                Button("React") { showReactionOptions = true }
            }
        }
    }

    private var reactionsButton: some View {
        TelegramMessageReactionsView(reactions: messageReactions) {
            showReactionDetails = true
        }
        .accessibilityHidden(!isPollMessage)
        .fixedSize(horizontal: true, vertical: false)
        .layoutPriority(2)
        .contextMenu { messageActions }
    }

    private func linkAccessibilityGroup(_ content: some View) -> some View {
        content
            .accessibilityElement(children: .contain)
            .accessibilityChildren {
                ForEach(messageLinks) { link in
                    Link(link.displayedText, destination: link.url)
                        .macModified {
                            if let destination = linkAccessibilityDestination(link) {
                                $0.accessibilityValue(destination)
                            } else {
                                $0
                            }
                        }
                }
                if let preview = separatePreviewAccessibilityLink, let destination = preview.url {
                    Link(preview.accessibilityLinkLabel, destination: destination)
                }
                if !messageReactions.isEmpty {
                    Button("Reactions") { showReactionDetails = true }
                        .accessibilityValue(telegramReactionDescription(messageReactions) ?? "")
                }
            }
            .accessibilityIdentifier("message-\(message.id)")
            .accessibilityLabel(accessibilityDescription)
            .accessibilityRespondsToUserInteraction(true)
            .modifier(OptionalAccessibilityActivation(
                isEnabled: hasDefaultActivation,
                action: activateMessage,
            ))
            .accessibilityActions { messageAccessibilityActions }
            .contextMenu { messageActions }
    }

    private func albumAccessibilityRepresentation(_ content: some View) -> some View {
        content
            .accessibilityRepresentation {
                VStack {
                    Text("Album message")
                        .accessibilityIdentifier("message-\(message.id)")
                        .accessibilityLabel(albumAccessibilityDescription)
                        .accessibilityRespondsToUserInteraction(true)
                        .accessibilityActions { messageAccessibilityActions }

                    ForEach(Array(albumMessages.enumerated()), id: \.offset) { index, albumMessage in
                        Button(albumItemAccessibilityLabel(albumMessage, index: index)) {
                            selectedAlbumMessage = albumMessage
                        }
                    }

                    ForEach(messageLinks) { link in
                        Link(link.displayedText, destination: link.url)
                            .macModified {
                                if let destination = linkAccessibilityDestination(link) {
                                    $0.accessibilityValue(destination)
                                } else {
                                    $0
                                }
                            }
                    }

                    if !messageReactions.isEmpty {
                        Button("Reactions") { showReactionDetails = true }
                            .accessibilityValue(telegramReactionDescription(messageReactions) ?? "")
                    }
                }
            }
    }

    private func messageAccessibilityElement(_ content: some View) -> some View {
        content
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("message-\(message.id)")
            .accessibilityLabel(accessibilityDescription)
            .accessibilityHint(activationHint)
            .modifier(OptionalAccessibilityActivation(
                isEnabled: hasDefaultActivation,
                action: activateMessage,
            ))
            .accessibilityActions { messageAccessibilityActions }
    }

    /// Cold-opening a chat reveals dozens of rows at once, whose photo/thumbnail loads (already
    /// cached, so they resolve almost together) previously each called `NSImage(contentsOfFile:)`
    /// synchronously on the MainActor with no yield point in between - decoding ~30 images
    /// back-to-back that way is enough by itself to freeze the UI for several seconds. Decoding
    /// off the main actor and only handing back the finished `NSImage` avoids that pile-up.
    private static func decodedImage(atPath path: String) async -> NSImage? {
        await Task.detached(priority: .userInitiated) {
            NSImage(contentsOfFile: path)
        }.value
    }

    private func albumItemAccessibilityLabel(_ albumMessage: Message, index: Int) -> String {
        "Item \(index + 1) of \(albumMessages.count), \(telegramMessageContentDescription(albumMessage))"
    }

    private func copyMessageText() {
        guard let text = copyableMessageText(message) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func openDocument() {
        if let documentPath {
            NSWorkspace.shared.open(URL(filePath: documentPath))
            return
        }
        guard !isLoadingDocument, let documentFileId else { return }
        isLoadingDocument = true
        Task {
            defer { isLoadingDocument = false }
            guard let path = await model.localDocumentPath(fileId: documentFileId) else { return }
            documentPath = path
            NSWorkspace.shared.open(URL(filePath: path))
        }
    }

    private func activateMessage() {
        if case .messageVoiceNote(let content) = message.content, let voicePath {
            audioPlayer.stop()
            player.toggle(
                fileId: content.voiceNote.voice.id,
                path: voicePath,
                duration: content.voiceNote.duration,
            )
        } else if case .messageAudio(let content) = message.content {
            player.stop()
            audioPlayer.toggle(
                audio: content.audio,
                service: model.service,
                playlist: audioPlaylist,
            )
        } else if case .messageDocument = message.content {
            openDocument()
        } else if case .messagePhoto = message.content, photoImage != nil {
            showPhotoPreview = true
        } else if case .messageVideo = message.content {
            showVideoPreview = true
        }
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

@MainActor func macMessageAccessibilityDescription(
    model: MacSessionModel,
    message: Message,
    lastReadOutboxMessageId: Int64,
    voicePlayer: MacVoicePlayer,
    audioPlayer: TelegramAudioPlayer,
) -> String {
    var parts = [String]()
    if let forwardedFrom = model.messageForwardedFrom[message.id] {
        parts.append("Forwarded from \(forwardedFrom)")
    }
    if let replyContext = model.messageReplyContexts[message.id] {
        parts.append("Replying to \(replyContext.senderName)")
    }

    let displayedText = model.messageServiceDescriptions[message.id]
        ?? telegramMessageContentDescription(message)
    if TelegramServiceMessage.isServiceMessage(message.content) {
        parts.append(displayedText)
    } else {
        if message.isOutgoing {
            parts.append("You")
        } else if let senderName = model.cachedSenderName(for: message) {
            parts.append(senderName)
        }
        parts.append(displayedText)
    }

    if let editStatus = telegramMessageEditStatus(message) {
        parts.append(editStatus)
    }
    parts.append(telegramMessageDateDescription(message.date))
    if let status = telegramMessageDeliveryStatus(
        message,
        lastReadOutboxMessageId: lastReadOutboxMessageId,
    ) {
        parts.append(status)
    }
    if case .messageVoiceNote(let content) = message.content {
        let elapsed = voicePlayer.currentFileId == content.voiceNote.voice.id
            ? voicePlayer.currentTime
            : 0
        parts.append(telegramVoicePlaybackDescription(
            duration: content.voiceNote.duration,
            elapsed: elapsed,
        ))
    }
    if case .messageAudio(let content) = message.content {
        let elapsed = audioPlayer.currentFileId == content.audio.audio.id
            ? audioPlayer.currentTime
            : 0
        parts.append(telegramVoicePlaybackDescription(
            duration: content.audio.duration,
            elapsed: elapsed,
        ))
        if audioPlayer.currentFileId == content.audio.audio.id {
            if audioPlayer.isBuffering {
                parts.append("Buffering")
            }
            if let playbackError = audioPlayer.playbackError {
                parts.append(playbackError)
            }
        }
    }
    if let replyContext = model.messageReplyContexts[message.id] {
        parts.append("Quoted message: \(replyContext.quotedText)")
    }
    return parts.joined(separator: ", ")
}

// MARK: - OptionalAccessibilityActivation

private struct OptionalAccessibilityActivation: ViewModifier {
    let isEnabled: Bool
    let action: () -> Void

    func body(content: Content) -> some View {
        if isEnabled {
            content.accessibilityAction {
                action()
            }
        } else {
            content
        }
    }
}

private extension View {
    func macModified(
        @ViewBuilder _ transform: (Self) -> some View,
    ) -> some View {
        transform(self)
    }
}

func macMessageText(_ message: Message) -> String {
    telegramMessageContentDescription(message)
}

private func copyableMessageText(_ message: Message) -> String? {
    switch message.content {
    case .messageText(let content): content.text.text.isEmpty ? nil : content.text.text
    case .messagePhoto(let content): content.caption.text.isEmpty ? nil : content.caption.text
    case .messageVideo(let content): content.caption.text.isEmpty ? nil : content.caption.text
    case .messageVoiceNote(let content): content.caption.text.isEmpty ? nil : content.caption.text
    case .messageAudio(let content): content.caption.text.isEmpty ? nil : content.caption.text
    case .messageDocument(let content): content.caption.text.isEmpty ? nil : content.caption.text
    default: nil
    }
}

private func editableMessageText(_ message: Message) -> String? {
    switch message.content {
    case .messageText(let content): content.text.text
    case .messagePhoto(let content): content.caption.text
    case .messageVideo(let content): content.caption.text
    case .messageVoiceNote(let content): content.caption.text
    case .messageAudio(let content): content.caption.text
    case .messageDocument(let content): content.caption.text
    default: nil
    }
}
