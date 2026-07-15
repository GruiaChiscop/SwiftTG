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
    let lastReadOutboxMessageId: Int64

    var body: some View {
        HStack {
            if message.isOutgoing {
                Spacer(minLength: 80)
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
                    .accessibilityHint(replyContext.quotedText)
                }
                if case .messageDocument(let content) = message.content {
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
                        voiceNote: content.voiceNote,
                        path: voicePath,
                        player: player,
                    )
                } else {
                    Text(macMessageText(message))
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
            .background(
                message.isOutgoing ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12),
                in: RoundedRectangle(cornerRadius: 12),
            )
            if !message.isOutgoing {
                Spacer(minLength: 80)
            }
        }
        .onScrollVisibilityChange(threshold: 0.01) { isVisible in
            self.isVisible = isVisible
        }
        .task(id: presentationTaskID) {
            guard await waitForStableVisibility(), let voiceFileId else { return }
            voicePath = await model.localVoiceNotePath(fileId: voiceFileId)
        }
        .task(id: presentationTaskID) {
            guard await waitForStableVisibility(),
                  let photoFileId,
                  let path = await model.localPhotoPath(fileId: photoFileId)
            else {
                photoPath = nil
                photoImage = nil
                return
            }
            photoPath = path
            photoImage = NSImage(contentsOfFile: path)
        }
        .task(id: presentationTaskID) {
            guard await waitForStableVisibility(),
                  let videoThumbnailFileId,
                  let path = await model.localPhotoPath(fileId: videoThumbnailFileId)
            else {
                videoThumbnailImage = nil
                return
            }
            videoThumbnailImage = NSImage(contentsOfFile: path)
        }
        .task(id: presentationTaskID) {
            guard await waitForStableVisibility() else { return }
            await model.loadCapabilities(for: message)
        }
        .task(id: presentationTaskID) {
            guard await waitForStableVisibility() else { return }
            await model.loadReplyContext(for: message)
        }
        .task(id: presentationTaskID) {
            guard await waitForStableVisibility() else { return }
            await model.loadForwardedFrom(for: message)
        }
        .task(id: presentationTaskID) {
            guard await waitForStableVisibility() else { return }
            await model.loadSenderName(for: message)
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityHint(activationHint)
        .modifier(OptionalAccessibilityActivation(
            isEnabled: hasDefaultActivation,
            action: activateMessage,
        ))
        .accessibilityActions {
            if capabilities?.properties.canBeReplied == true {
                Button("Reply") { model.beginReply(to: message) }
            }
            if model.messageReplyContexts[message.id]?.messageId != nil {
                Button("Go to Replied Message") { model.navigateToRepliedMessage(from: message) }
            }
            if let forwardedFrom = model.messageForwardedFrom[message.id], canNavigateToForwardOrigin {
                Button("Go to \(forwardedFrom)") { model.navigateToForwardOrigin(from: message) }
            }
            if capabilities?.canReactWithHeart == true {
                Button("React") { model.reactWithHeart(to: message) }
            }
            if canCopy {
                Button("Copy") { copyMessageText() }
            }
            if photoImage != nil {
                Button("Open Photo") { showPhotoPreview = true }
            }
            if videoFileId != nil {
                Button("Play Video") { showVideoPreview = true }
            }
            if capabilities?.properties.canBeEdited == true, editableMessageText(message) != nil {
                Button("Edit") { model.beginEditing(message) }
            }
            if capabilities?.properties.canBePinned == true {
                Button(message.isPinned ? "Unpin" : "Pin") { model.togglePin(for: message) }
            }
            if canDelete {
                Button("Delete") { showDeleteOptions = true }
            }
        }
        // Attach the context menu after creating the combined accessibility
        // element so VoiceOver's VO-Shift-M "Show Menu" action reaches it.
        .contextMenu { messageActions }
    }

    // MARK: Private

    @State private var player = MacVoicePlayer.shared
    @State private var documentPath: String?
    @State private var isLoadingDocument = false
    @State private var photoImage: NSImage?
    @State private var photoPath: String?
    @State private var videoThumbnailImage: NSImage?
    @State private var voicePath: String?
    @State private var showDeleteOptions = false
    @State private var showPhotoPreview = false
    @State private var showVideoPreview = false
    @State private var isVisible = false

    private var capabilities: MacMessageCapabilities? {
        model.messageCapabilities[message.id]
    }

    private var presentationTaskID: String {
        "\(isVisible):\(message.id):\(message.editDate)"
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

    private var documentFileId: Int? {
        guard case .messageDocument(let content) = message.content else { return nil }
        return content.document.document.id
    }

    private var activationHint: String {
        if voiceFileId != nil {
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
        voiceFileId != nil || documentFileId != nil || photoFileId != nil || videoFileId != nil
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
        var parts = [String]()
        if let forwardedFrom = model.messageForwardedFrom[message.id] {
            parts.append("Forwarded from \(forwardedFrom)")
        }
        if let replyContext = model.messageReplyContexts[message.id] {
            parts.append("Replying to \(replyContext.senderName)")
        }
        if message.isOutgoing {
            parts.append("You")
        } else if let senderName = model.cachedSenderName(for: message) {
            parts.append(senderName)
        }
        parts.append(telegramMessageContentDescription(message))
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
            let elapsed = player.currentFileId == content.voiceNote.voice.id ? player.currentTime : 0
            parts.append(telegramVoicePlaybackDescription(
                duration: content.voiceNote.duration,
                elapsed: elapsed,
            ))
        }
        if let replyContext = model.messageReplyContexts[message.id] {
            parts.append("Quoted message: \(replyContext.quotedText)")
        }
        return parts.joined(separator: ", ")
    }

    @ViewBuilder private var messageActions: some View {
        if capabilities?.properties.canBeReplied == true {
            Button("Reply", systemImage: "arrowshape.turn.up.left") { model.beginReply(to: message) }
        }
        if model.messageReplyContexts[message.id]?.messageId != nil {
            Button("Go to Replied Message", systemImage: "arrow.up.left") {
                model.navigateToRepliedMessage(from: message)
            }
        }
        if let forwardedFrom = model.messageForwardedFrom[message.id], canNavigateToForwardOrigin {
            Button("Go to \(forwardedFrom)", systemImage: "arrow.up.right.square") {
                model.navigateToForwardOrigin(from: message)
            }
        }
        if capabilities?.canReactWithHeart == true {
            Button("React", systemImage: "heart") { model.reactWithHeart(to: message) }
        }
        if canCopy {
            Button("Copy", systemImage: "doc.on.doc") { copyMessageText() }
        }
        if photoImage != nil {
            Button("Open Photo", systemImage: "photo") { showPhotoPreview = true }
        }
        if videoFileId != nil {
            Button("Play Video", systemImage: "play.rectangle") { showVideoPreview = true }
        }
        if capabilities?.properties.canBeEdited == true, editableMessageText(message) != nil {
            Button("Edit", systemImage: "square.and.pencil") { model.beginEditing(message) }
        }
        if capabilities?.properties.canBePinned == true {
            Button(message.isPinned ? "Unpin" : "Pin", systemImage: message.isPinned ? "pin.slash" : "pin") {
                model.togglePin(for: message)
            }
        }
        if canDelete {
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) {
                showDeleteOptions = true
            }
        }
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

    private func waitForStableVisibility() async -> Bool {
        do {
            try await Task.sleep(for: .milliseconds(100))
        } catch {
            return false
        }
        return isVisible && !Task.isCancelled
    }

    private func activateMessage() {
        if case .messageVoiceNote(let content) = message.content, let voicePath {
            player.toggle(
                fileId: content.voiceNote.voice.id,
                path: voicePath,
                duration: content.voiceNote.duration,
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

// MARK: - MacDocumentMessageContent

private struct MacDocumentMessageContent: View {
    let content: MessageDocument
    let isDownloaded: Bool
    let isLoading: Bool
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 8) {
                Image(systemName: "doc.fill")
                VStack(alignment: .leading, spacing: 2) {
                    Text(content.document.fileName)
                        .lineLimit(2)
                    if !content.caption.text.isEmpty {
                        Text(content.caption.text)
                            .foregroundStyle(.secondary)
                    }
                }
                if isLoading {
                    ProgressView()
                } else if !isDownloaded {
                    Image(systemName: "arrow.down.circle")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .accessibilityHidden(true)
    }
}

// MARK: - MacPhotoMessageContent

private struct MacPhotoMessageContent: View {
    let content: MessagePhoto
    let image: NSImage?
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 6) {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 360, maxHeight: 320)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    ProgressView("Loading photo…")
                        .frame(minWidth: 180, minHeight: 100)
                }
                if !content.caption.text.isEmpty {
                    Text(content.caption.text)
                        .textSelection(.enabled)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(image == nil)
        .accessibilityHidden(true)
    }
}

// MARK: - MacPhotoPreview

private struct MacPhotoPreview: View {
    // MARK: Internal

    let image: NSImage
    let caption: String
    let fileURL: URL

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Photo")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Close", systemImage: "xmark") { dismiss() }
                    .labelStyle(.iconOnly)
                    .keyboardShortcut(.cancelAction)
            }

            ScrollView([.horizontal, .vertical]) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(minWidth: 320, minHeight: 240)
                    .accessibilityLabel(caption.isEmpty ? "Photo" : "Photo: \(caption)")
            }

            if !caption.isEmpty {
                Text(caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }

            HStack {
                Spacer()
                Button("Open in Default App", systemImage: "arrow.up.forward.app") {
                    NSWorkspace.shared.open(fileURL)
                }
            }
        }
        .padding(16)
        .frame(minWidth: 600, minHeight: 480)
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
}

// MARK: - MacVideoMessageContent

private struct MacVideoMessageContent: View {
    // MARK: Internal

    let content: MessageVideo
    let thumbnail: NSImage?
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 6) {
                if content.showCaptionAboveMedia, !content.caption.text.isEmpty {
                    caption
                }

                ZStack {
                    if let thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 360, maxHeight: 320)
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.black.opacity(0.35))
                            .frame(width: 280, height: 180)
                    }

                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.white)
                        .shadow(radius: 3)

                    Text(telegramClockDuration(content.video.duration))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.7), in: Capsule())
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(8)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))

                if !content.showCaptionAboveMedia, !content.caption.text.isEmpty {
                    caption
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityHidden(true)
    }

    // MARK: Private

    private var caption: some View {
        Text(content.caption.text)
            .textSelection(.enabled)
    }
}

// MARK: - MacVideoPreview

private struct MacVideoPreview: View {
    // MARK: Internal

    @Bindable var model: MacSessionModel

    let fileId: Int
    let caption: String
    let duration: Int
    let startTimestamp: Int

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Video")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Close", systemImage: "xmark") { dismiss() }
                    .labelStyle(.iconOnly)
                    .keyboardShortcut(.cancelAction)
            }

            Group {
                if let player {
                    VideoPlayer(player: player)
                        .accessibilityLabel("Video, duration \(telegramClockDuration(duration))")
                } else if didFail {
                    ContentUnavailableView(
                        "Video Unavailable",
                        systemImage: "exclamationmark.triangle",
                        description: Text("The video could not be downloaded."),
                    )
                } else {
                    ProgressView("Downloading video…")
                        .accessibilityAddTraits(.updatesFrequently)
                }
            }
            .frame(minWidth: 640, minHeight: 360)

            if !caption.isEmpty {
                Text(caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }

            if let fileURL {
                HStack {
                    Spacer()
                    Button("Open in Default App", systemImage: "arrow.up.forward.app") {
                        NSWorkspace.shared.open(fileURL)
                    }
                }
            }
        }
        .padding(16)
        .frame(minWidth: 680, minHeight: 480)
        .task(id: fileId) {
            guard let path = await model.localVideoPath(fileId: fileId) else {
                didFail = true
                return
            }
            let url = URL(filePath: path)
            fileURL = url
            let player = AVPlayer(url: url)
            self.player = player
            if startTimestamp > 0 {
                await player.seek(to: CMTime(seconds: Double(startTimestamp), preferredTimescale: 600))
            }
            player.play()
        }
        .onDisappear { player?.pause() }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var fileURL: URL?
    @State private var didFail = false
}

// MARK: - MacVoiceMessageContent

private struct MacVoiceMessageContent: View {
    // MARK: Internal

    let voiceNote: VoiceNote
    let path: String?

    @Bindable var player: MacVoicePlayer

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button("Back 5 Seconds", systemImage: "gobackward.5") {
                    player.seekBackward()
                }
                .labelStyle(.iconOnly)
                .disabled(!isCurrent)

                Button(
                    isPlaying ? "Pause Voice Message" : "Play Voice Message",
                    systemImage: isPlaying
                        ? "pause.fill"
                        : "play.fill",
                ) {
                    guard let path else { return }
                    player.toggle(fileId: voiceNote.voice.id, path: path, duration: voiceNote.duration)
                }
                .labelStyle(.iconOnly)
                .disabled(path == nil)

                Button("Forward 5 Seconds", systemImage: "goforward.5") {
                    player.seekForward()
                }
                .labelStyle(.iconOnly)
                .disabled(!isCurrent)

                ProgressView(value: Double(elapsed), total: Double(max(1, voiceNote.duration)))
                    .frame(minWidth: 100)
            }

            Text("\(telegramClockDuration(elapsed)) / \(telegramClockDuration(voiceNote.duration))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .accessibilityHidden(true)
    }

    // MARK: Private

    private var elapsed: Int {
        isCurrent ? player.currentTime : 0
    }

    private var isCurrent: Bool {
        player.currentFileId == voiceNote.voice.id
    }

    private var isPlaying: Bool {
        isCurrent && player.isPlaying
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
    case .messageDocument(let content): content.caption.text
    default: nil
    }
}
