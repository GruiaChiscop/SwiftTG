// MacMessageRow.swift

import AppKit
import AVKit
import QuickLook
import SwiftUI
import TDLibKit

// MARK: - MacMessageRow

struct MacMessageRow: View {
    // MARK: Internal

    @Bindable var model: MacSessionModel

    let message: Message
    let albumMessages: [Message]
    let lastReadOutboxMessageId: Int64
    let showsSenderName: Bool
    let isChannelMessage: Bool

    /// Type-erased for the same reason as iOS's `MessageView.body` - see the comment there. This
    /// row's conditional-branch count (104 `if`/`else if`/`switch` occurrences) is even higher, so
    /// it carries the identical Swift-metadata-demangling risk without ever having been diagnosed
    /// here yet.
    var body: some View {
        AnyView(messageRowBody)
    }

    // MARK: Private

    /// Actions common to the context menu and VoiceOver's accessibility actions; kept as one list so
    /// the two presentations (menu buttons with icons vs. plain accessibility actions) can't drift.
    /// "React" and "Delete" are still special-cased below since each renders differently per surface
    /// (a reactions submenu vs. a single toggle; a destructive button with a leading divider vs. plain).
    private enum MacRowAction {
        case button(title: String, systemImage: String, isEnabled: Bool = true, action: () -> Void)
        case reactions
    }

    private enum DocumentTransferPhase: Equatable {
        case downloading
        case paused
        case preparingPreview
    }

    @Environment(\.telegramBubbleCornerRadius) private var bubbleCornerRadius
    @State private var player = MacVoicePlayer.shared
    @State private var audioPlayer = TelegramAudioPlayer.shared
    @State private var videoNotePlayer = TelegramVideoNotePlayer.shared
    @State private var documentPath: String?
    @State private var documentPreviewURL: URL?
    @State private var documentDownloadFile: File?
    @State private var documentTransferPhase: DocumentTransferPhase?
    @State private var documentTransferID: UUID?
    @State private var documentDownloadCancellationTask: Task<Void, Never>?
    @State private var isLoadingDocument = false
    @State private var photoImage: NSImage?
    @State private var photoPath: String?
    @State private var videoThumbnailImage: NSImage?
    @State private var videoNoteThumbnailImage: NSImage?
    @State private var gifThumbnailImage: NSImage?
    @State private var voicePath: String?
    @State private var showDeleteOptions = false
    @State private var showReactionOptions = false
    @State private var showReactionDetails = false
    @State private var isLoadingComments = false
    @State private var commentsErrorMessage: String?
    @State private var showPhotoPreview = false
    @State private var showVideoPreview = false
    @State private var showGifPreview = false
    @State private var showForwardPicker = false
    @State private var selectedAlbumMessage: Message?
    @State private var selectedStickerPack: TelegramStickerPackReference?
    @State private var pendingStickerFromPack: Sticker?
    @State private var stickerToEdit: Sticker?
    @State private var isSavingGif = false

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

    /// Unlike iOS - where every content type's caption funnels through one shared text render
    /// site - captions here are rendered inside each `Mac*MessageContent` view individually, so
    /// swapping in a translation cleanly only works for plain text messages for now. Backed by
    /// `model.messageTranslationEligibility`, loaded once via `loadTranslationEligibility(for:)`
    /// rather than computed live here (see that function's doc comment for why).
    private var canTranslate: Bool {
        model.messageTranslationEligibility[message.id] ?? false
    }

    private var showsTranslation: Bool {
        model.translationShownMessageIds.contains(message.id)
    }

    private var displayedFormattedText: FormattedText? {
        showsTranslation ? model.messageTranslations[message.id] : nil
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

    private var messageContact: MessageContact? {
        guard case .messageContact(let content) = message.content else { return nil }
        return content
    }

    private var locationPresentation: TelegramLocationPresentation? {
        TelegramLocationPresentation(message.content)
    }

    private var documentTransferStatus: String? {
        guard case .messageDocument(let content) = message.content else { return nil }
        return switch documentTransferPhase {
        case .downloading:
            TelegramFileTransferProgress.downloadStatus(
                fileName: content.document.fileName,
                file: documentDownloadFile,
            )
        case .paused:
            "Download paused, \(content.document.fileName)"
        case .preparingPreview:
            "Preparing preview for \(content.document.fileName)"
        case nil:
            nil
        }
    }

    private var documentTransferProgress: Double? {
        guard documentTransferPhase == .downloading else { return nil }
        return TelegramFileTransferProgress.fraction(documentDownloadFile)
    }

    private var documentTransferLabel: String? {
        switch documentTransferPhase {
        case .downloading:
            TelegramFileTransferProgress.downloadLabel(file: documentDownloadFile)
        case .paused:
            "Download paused"
        case .preparingPreview:
            "Preparing preview"
        case nil:
            nil
        }
    }

    private var hasDefaultActivation: Bool {
        voiceFileId != nil || audioFileId != nil || documentFileId != nil || photoFileId != nil
            || videoFileId != nil || videoNoteFileId != nil || gifFileId != nil || messageContact != nil
            || locationPresentation != nil
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

    private var videoNoteFileId: Int? {
        guard case .messageVideoNote(let content) = message.content else { return nil }
        return content.videoNote.video.id
    }

    private var videoNoteThumbnailFileId: Int? {
        guard case .messageVideoNote(let content) = message.content else { return nil }
        return content.videoNote.thumbnail?.file.id
    }

    private var gifFileId: Int? {
        guard case .messageAnimation(let content) = message.content else { return nil }
        return content.animation.animation.id
    }

    private var gifThumbnailFileId: Int? {
        guard case .messageAnimation(let content) = message.content else { return nil }
        return content.animation.thumbnail?.file.id
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

    private var showsVisualSenderName: Bool {
        showsSenderName && !message.isOutgoing && !isServiceMessage
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

    private var stickerPackReference: TelegramStickerPackReference? {
        guard case .messageSticker(let content) = message.content else { return nil }
        return TelegramStickerPackReference(messageSticker: content)
    }

    private var editableSticker: Sticker? {
        guard case .messageSticker(let content) = message.content,
              TelegramStickerPresentation(content.sticker).isEditable
        else { return nil }
        return content.sticker
    }

    private var favoriteStickerAction: TelegramStickerFavoriteAction? {
        guard case .messageSticker(let content) = message.content else { return nil }
        return model.favoriteStickers.action(for: content.sticker)
    }

    private var savableGifFileID: Int? {
        TelegramMessageGifSaving.fileID(from: message)
    }

    private var isPollMessage: Bool {
        if case .messagePoll = message.content {
            true
        } else {
            false
        }
    }

    private var isChecklistMessage: Bool {
        if case .messageChecklist = message.content {
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
        !isPollMessage && !isChecklistMessage &&
            (!messageReactions.isEmpty || !messageLinks.isEmpty || separatePreviewAccessibilityLink != nil)
    }

    private var rowActions: [MacRowAction] {
        var items = [MacRowAction]()
        if isChannelMessage, let replyInfo = message.interactionInfo?.replyInfo {
            items.append(.button(
                title: replyInfo.replyCount > 0 ? "View Comments" : "Add Comment",
                systemImage: "bubble.left",
            ) { openComments() })
        }
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
        if stickerPackReference != nil {
            items.append(.button(title: "View Sticker Pack", systemImage: "square.stack.3d.up") {
                selectedStickerPack = stickerPackReference
            })
        }
        if let favoriteStickerAction {
            items.append(.button(
                title: favoriteStickerAction.title,
                systemImage: favoriteStickerAction.systemImage,
            ) { toggleStickerFavorite() })
        }
        if editableSticker != nil {
            items.append(.button(title: "Edit Sticker", systemImage: "pencil.and.outline") {
                stickerToEdit = editableSticker
            })
        }
        if savableGifFileID != nil {
            items.append(.button(
                title: "Save to GIFs",
                systemImage: "photo.on.rectangle.angled",
                isEnabled: !isSavingGif,
                action: saveGif,
            ))
        }
        if canCopy {
            items.append(.button(title: "Copy", systemImage: "doc.on.doc") { copyMessageText() })
        }
        if canTranslate {
            items.append(.button(
                title: model.translationShownMessageIds.contains(message.id) ? "Show Original" : "Translate",
                systemImage: "character.bubble",
            ) { model.toggleTranslation(for: message) })
        }
        if documentFileId != nil {
            items.append(.button(title: "Save As…", systemImage: "square.and.arrow.down") {
                saveDocument()
            })
        }
        if !isVisualAlbum, photoImage != nil {
            items.append(.button(title: "Open Photo", systemImage: "photo") { showPhotoPreview = true })
        }
        if !isVisualAlbum, videoFileId != nil {
            items.append(.button(title: "Play Video", systemImage: "play.rectangle") { showVideoPreview = true })
        }
        if videoNoteFileId != nil {
            items.append(.button(title: "Play Video Message", systemImage: "video.circle") { activateMessage() })
        }
        if !isVisualAlbum, gifFileId != nil {
            items.append(.button(title: "Play GIF", systemImage: "play.rectangle") { showGifPreview = true })
        }
        if let messageContact {
            let presentation = TelegramContactPresentation(messageContact)
            items.append(.button(
                title: presentation.hasTelegramAccount ? "Message" : "Add to Contacts",
                systemImage: presentation.hasTelegramAccount ? "message" : "person.crop.circle.badge.plus",
            ) { activateMessage() })
        }
        if locationPresentation != nil {
            items.append(.button(title: "Open in Maps", systemImage: "location") { activateMessage() })
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

    private var checklistAccessibilityContextDescription: String {
        var parts = [message.isOutgoing ? "You" : model.cachedSenderName(for: message) ?? "Unknown sender"]
        if case .messageChecklist(let content) = message.content {
            parts.append(TelegramChecklistPresentation(content).contentDescription)
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

    private var commentsErrorIsPresented: Binding<Bool> {
        Binding(
            get: { commentsErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    commentsErrorMessage = nil
                }
            },
        )
    }

    private var messageRowBody: some View {
        HStack {
            if isServiceMessage || message.isOutgoing {
                Spacer(minLength: 80)
            }
            HStack(alignment: .bottom, spacing: 5) {
                if message.isOutgoing, !messageReactions.isEmpty {
                    reactionsButton
                }
                VStack(alignment: .leading, spacing: 4) {
                    if showsVisualSenderName, let senderName = model.cachedSenderName(for: message) {
                        Text(senderName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tint)
                            .lineLimit(1)
                            .accessibilityHidden(true)
                    }

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
                            isPaused: documentTransferPhase == .paused,
                            interactionIsDisabled: documentTransferPhase == .preparingPreview,
                            transferProgress: documentTransferProgress,
                            transferStatus: documentTransferLabel,
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
                    } else if case .messageVideoNote(let content) = message.content {
                        MacVideoNoteMessageContent(
                            content: content,
                            thumbnail: videoNoteThumbnailImage,
                            service: model.service,
                            player: videoNotePlayer,
                        )
                    } else if case .messageAnimation(let content) = message.content {
                        MacGifMessageContent(
                            content: content,
                            thumbnail: gifThumbnailImage,
                            onOpen: { showGifPreview = true },
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
                    } else if case .messageContact(let content) = message.content {
                        MacContactMessageContent(content: content, onOpen: activateMessage)
                    } else if let locationPresentation {
                        MacLocationMessageContent(presentation: locationPresentation, onOpen: activateMessage)
                    } else if case .messagePoll(let content) = message.content {
                        TelegramPollView(content: content, message: message, service: model.service) {
                            Text(content.poll.question.text)
                                .accessibilityIdentifier("message-\(message.id)")
                                .accessibilityLabel(pollAccessibilityContextDescription)
                                .accessibilityActions { messageAccessibilityActions }
                        }
                    } else if case .messageChecklist(let content) = message.content {
                        TelegramChecklistView(
                            content: content,
                            message: message,
                            canMarkTasksAsDone: capabilities?.properties.canMarkTasksAsDone ?? false,
                            service: model.service,
                        ) {
                            Text(content.list.title.text)
                                .accessibilityIdentifier("message-\(message.id)")
                                .accessibilityLabel(checklistAccessibilityContextDescription)
                                .accessibilityActions { messageAccessibilityActions }
                        }
                    } else if case .messageText(let content) = message.content {
                        if let linkPreview = content.linkPreview, linkPreview.showAboveText {
                            MacLinkPreviewView(model: model, preview: linkPreview)
                        }
                        if !content.text.text.isEmpty {
                            MacFormattedTextView(formattedText: displayedFormattedText ?? content.text)
                            if showsTranslation {
                                Text("Translated")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .accessibilityHidden(true)
                            }
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
                    .accessibilityHidden(true)

                    if isChannelMessage, let replyInfo = message.interactionInfo?.replyInfo {
                        TelegramCommentsBar(replyCount: replyInfo.replyCount, isLoading: isLoadingComments) {
                            openComments()
                        }
                    }
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background {
                    if !isStickerMessage {
                        RoundedRectangle(cornerRadius: bubbleCornerRadius)
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
                    if isPollMessage || isChecklistMessage {
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
            guard let videoNoteThumbnailFileId,
                  let path = await model.localPhotoPath(fileId: videoNoteThumbnailFileId)
            else {
                videoNoteThumbnailImage = nil
                return
            }
            videoNoteThumbnailImage = await Self.decodedImage(atPath: path)
        }
        .task(id: presentationTaskID) {
            guard !isVisualAlbum,
                  let gifThumbnailFileId,
                  let path = await model.localPhotoPath(fileId: gifThumbnailFileId)
            else {
                gifThumbnailImage = nil
                return
            }
            gifThumbnailImage = await Self.decodedImage(atPath: path)
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
        .task(id: presentationTaskID) {
            model.loadTranslationEligibility(for: message)
        }
        .onReceive(model.service.filePublisher(fileId: documentFileId ?? 0)) { file in
            guard file.id == documentFileId else { return }
            documentDownloadFile = file
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
        .sheet(isPresented: $showGifPreview) {
            if case .messageAnimation(let content) = message.content {
                MacGifPreview(
                    model: model,
                    fileId: content.animation.animation.id,
                    caption: content.caption.text,
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
        .sheet(item: $selectedStickerPack) { reference in
            TelegramStickerPackPreview(
                reference: reference,
                service: model.service,
                chatId: message.chatId,
                onSelect: { pendingStickerFromPack = $0 },
                preview: { sticker in
                    MacStickerView(
                        model: model,
                        sticker: sticker,
                        maxSide: 76,
                        playsAnimation: false,
                    )
                },
            )
        }
        .sheet(item: $stickerToEdit) { sticker in
            TelegramStickerEditor(
                sticker: sticker,
                service: model.service,
                chatId: message.chatId,
                actionTitle: "Send",
                onSave: { output, emojis in
                    try await TelegramStickerEditing.sendEditedSticker(
                        output: output,
                        emojis: emojis,
                        service: model.service,
                        chatId: message.chatId,
                        topicId: model.openedTopic,
                    )
                },
            )
        }
        .task(id: pendingStickerFromPack?.sticker.id) { await sendPendingStickerFromPack() }
        .sheet(isPresented: $showReactionDetails) {
            TelegramReactionDetailsView(
                service: model.service,
                chatId: message.chatId,
                messageId: message.id,
            )
        }
        .alert("Couldn't Open Comments", isPresented: commentsErrorIsPresented) {
            Button("OK") {}
        } message: {
            Text(commentsErrorMessage ?? "")
        }
        .sheet(isPresented: $showForwardPicker) {
            MacForwardChatPicker(model: model, message: message)
        }
        .quickLookPreview($documentPreviewURL)
    }

    @ViewBuilder private var messageActions: some View {
        ForEach(Array(rowActions.enumerated()), id: \.offset) { _, item in
            switch item {
            case .button(let title, let systemImage, let isEnabled, let action):
                Button(title, systemImage: systemImage, action: action)
                    .disabled(!isEnabled)
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
            case .button(let title, _, let isEnabled, let action):
                Button(title, action: action)
                    .disabled(!isEnabled)
            case .reactions:
                Button("React") { showReactionOptions = true }
            }
        }
    }

    private var reactionsButton: some View {
        TelegramMessageReactionsView(reactions: messageReactions) {
            showReactionDetails = true
        }
        .accessibilityHidden(!isPollMessage && !isChecklistMessage)
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
                            if let destination = TelegramTextFormatting.accessibilityDestination(for: link) {
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
                                if let destination = TelegramTextFormatting.accessibilityDestination(for: link) {
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
            .accessibilityValue(documentTransferStatus ?? "")
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

    private func toggleStickerFavorite() {
        guard case .messageSticker(let content) = message.content,
              favoriteStickerAction != nil
        else { return }
        model.messageActionError = nil
        Task { @MainActor in
            do {
                try await model.favoriteStickers.toggle(content.sticker)
            } catch is CancellationError {
                return
            } catch {
                model.messageActionError = "Favorites couldn't be updated: \(telegramErrorDescription(error))"
            }
        }
    }

    private func saveGif() {
        guard let fileID = savableGifFileID, !isSavingGif else { return }
        isSavingGif = true
        model.messageActionError = nil
        Task { @MainActor in
            defer { isSavingGif = false }
            do {
                try await TelegramMessageGifSaving.save(fileID: fileID, service: model.service)
            } catch is CancellationError {
                return
            } catch {
                model.messageActionError = "GIF couldn't be saved: \(telegramErrorDescription(error))"
            }
        }
    }

    @MainActor private func sendPendingStickerFromPack() async {
        guard let sticker = pendingStickerFromPack else { return }
        defer { pendingStickerFromPack = nil }
        model.messageActionError = nil
        do {
            try await TelegramStickerSending.send(
                sticker,
                service: model.service,
                chatId: message.chatId,
                replyToMessageId: nil,
                topicId: model.openedTopic,
            )
        } catch is CancellationError {
            return
        } catch {
            model.messageActionError = "Sticker couldn't be sent: \(telegramErrorDescription(error))"
        }
    }

    private func openDocument() {
        guard let documentFileId,
              case .messageDocument(let content) = message.content
        else { return }

        if documentTransferPhase == .downloading {
            pauseDocumentDownload(fileId: documentFileId)
            return
        }
        guard documentTransferPhase != .preparingPreview else { return }

        let transferID = UUID()
        let pendingCancellation = documentDownloadCancellationTask
        documentDownloadCancellationTask = nil
        documentTransferID = transferID
        isLoadingDocument = true
        model.messageActionError = nil
        documentTransferPhase = documentPath == nil ? .downloading : .preparingPreview
        Task { @MainActor in
            defer {
                if documentTransferID == transferID {
                    documentTransferID = nil
                    isLoadingDocument = false
                    documentTransferPhase = nil
                }
            }
            do {
                await pendingCancellation?.value
                guard documentTransferID == transferID else { return }
                let resolvedPath: String
                if let documentPath {
                    resolvedPath = documentPath
                } else if let path = await model.localDocumentPath(
                    file: content.document.document,
                    suggestedFileName: content.document.fileName,
                ) {
                    guard documentTransferID == transferID else { return }
                    resolvedPath = path
                    documentPath = path
                } else {
                    guard documentTransferID == transferID else { return }
                    throw TelegramFileTransferError.sourceUnavailable
                }
                if documentTransferPhase != .preparingPreview {
                    documentTransferPhase = .preparingPreview
                }
                documentPreviewURL = try await TelegramDocumentExport.previewURL(
                    sourceURL: URL(filePath: resolvedPath),
                    suggestedFileName: content.document.fileName,
                    mimeType: content.document.mimeType,
                    identifier: String(documentFileId),
                )
            } catch {
                guard !Task.isCancelled, documentTransferID == transferID else { return }
                model.messageActionError = "File couldn't be previewed: \(telegramErrorDescription(error))"
            }
        }
    }

    private func pauseDocumentDownload(fileId: Int) {
        documentTransferID = nil
        isLoadingDocument = false
        documentTransferPhase = .paused
        let service = model.service
        documentDownloadCancellationTask = Task {
            _ = try? await service.cancelDownloadFile(
                fileId: fileId,
                onlyIfPending: false,
            )
        }
    }

    private func saveDocument() {
        guard !isLoadingDocument,
              case .messageDocument(let content) = message.content
        else { return }

        let panel = NSSavePanel()
        panel.title = "Save File"
        panel.prompt = "Save"
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = TelegramDocumentExport.fileName(content.document.fileName)
        guard panel.runModal() == .OK, let destinationURL = panel.url else { return }

        isLoadingDocument = true
        model.messageActionError = nil
        Task { @MainActor in
            defer { isLoadingDocument = false }
            let resolvedPath: String? =
                if let documentPath {
                    documentPath
                } else {
                    await model.localDocumentCachePath(fileId: content.document.document.id)
                }
            guard let path = resolvedPath else {
                model.messageActionError = "File couldn't be downloaded."
                return
            }

            do {
                try await TelegramDocumentExport.copyFile(
                    from: URL(filePath: path),
                    to: destinationURL,
                )
            } catch {
                model.messageActionError = "File couldn't be saved: \(telegramErrorDescription(error))"
            }
        }
    }

    /// Resolves the comment thread's discussion group/`messageThreadId` before switching to it -
    /// mirrors iOS's `openComments()`, so there's no empty screen that fills in after the fact.
    private func openComments() {
        guard !isLoadingComments else { return }
        isLoadingComments = true
        commentsErrorMessage = nil

        Task {
            defer { isLoadingComments = false }
            do {
                let thread = try await model.service.getMessageThread(
                    chatId: message.chatId,
                    messageId: message.id,
                )
                let replyCount = message.interactionInfo?.replyInfo?.replyCount ?? 0
                let title = replyCount > 0 ? "\(replyCount) Comment\(replyCount == 1 ? "" : "s")" : "Comments"
                await model.openCommentThread(
                    discussionChatId: thread.chatId,
                    messageThreadId: thread.messageThreadId,
                    title: title,
                )
            } catch {
                guard !Task.isCancelled else { return }
                commentsErrorMessage = telegramErrorDescription(error)
            }
        }
    }

    private func activateMessage() {
        if case .messageVideoNote(let content) = message.content {
            player.stop()
            audioPlayer.stop()
            videoNotePlayer.toggle(videoNote: content.videoNote, service: model.service)
        } else if case .messageVoiceNote(let content) = message.content, let voicePath {
            videoNotePlayer.stop()
            audioPlayer.stop()
            player.toggle(
                fileId: content.voiceNote.voice.id,
                path: voicePath,
                duration: content.voiceNote.duration,
            )
        } else if case .messageAudio(let content) = message.content {
            videoNotePlayer.stop()
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
            videoNotePlayer.stop()
            showVideoPreview = true
        } else if case .messageAnimation = message.content {
            videoNotePlayer.stop()
            showGifPreview = true
        } else if let messageContact {
            let presentation = TelegramContactPresentation(messageContact)
            if presentation.hasTelegramAccount {
                model.navigateToContact(userId: presentation.userId)
            } else {
                model.addContact(presentation)
            }
        } else if let locationPresentation {
            let latitude = locationPresentation.location.latitude
            let longitude = locationPresentation.location.longitude
            guard let url = URL(string: "http://maps.apple.com/?ll=\(latitude),\(longitude)") else { return }
            NSWorkspace.shared.open(url)
        }
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

    let translatedText = model.translationShownMessageIds.contains(message.id)
        ? model.messageTranslations[message.id]?.text
        : nil
    let contentDescription = translatedText?.isEmpty == false
        ? translatedText!
        : telegramMessageContentDescription(message)
    let displayedText = model.messageServiceDescriptions[message.id] ?? contentDescription
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
    if translatedText?.isEmpty == false {
        parts.append("Translated")
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
    if case .messageVideoNote(let content) = message.content {
        parts.append(TelegramVideoNotePresentation(
            content,
            isOutgoing: message.isOutgoing,
        ).accessibilityDetails)
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
    case .messageAnimation(let content): content.caption.text.isEmpty ? nil : content.caption.text
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
    case .messageAnimation(let content): content.caption.text
    case .messageVoiceNote(let content): content.caption.text
    case .messageAudio(let content): content.caption.text
    case .messageDocument(let content): content.caption.text
    default: nil
    }
}
