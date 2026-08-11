// MessageComposer.swift

import SwiftUI
import TDLibKit

/// Staging, editing, and sending of a chat's outgoing text/photo/document/voice-note content.
/// Split out of `ChatVM`, which composes this alongside `VoiceRecordingController` and keeps its
/// own scope to history loading, rendering, and navigation.
@MainActor @Observable final class MessageComposer {
    // MARK: Lifecycle

    init(chatId: Int64, service: any TelegramService, draftMessage: DraftMessage?, topicId: MessageTopic? = nil) {
        self.chatId = chatId
        self.service = service
        self.topicId = topicId
        self.linkPreviewComposer = TelegramLinkPreviewComposer(service: service)
        self.editLinkPreviewComposer = TelegramLinkPreviewComposer(service: service)
        if let draftMessage,
           case .draftMessageContentText(let draftMessageContentText) = draftMessage.content
        {
            linkPreviewComposer.configure(preview: nil, options: draftMessageContentText.linkPreviewOptions)
            self.text = getAttributedString(from: draftMessageContentText.text, linkStyle: .composer)
            linkPreviewComposer.update(text: draftMessageContentText.text)
        }
    }

    deinit {
        MainActor.assumeIsolated {
            for url in displayedDocuments {
                TelegramOutgoingFileStaging.shared.discard(fileURL: url)
            }
            for image in displayedImages {
                TelegramOutgoingFileStaging.shared.discard(fileURL: image.url)
            }
        }
    }

    // MARK: Internal

    var editCustomMessage: CustomMessage?
    var replyMessage: CustomMessage?
    var showSendButton = false
    var showDetail = false
    var displayedImages = [SelectedImage]()
    var displayedDocuments = [URL]()
    var showCameraView = false
    var showDocumentPicker = false
    var showPhotoPickerView = false
    var isSubmittingMessage = false
    @ObservationIgnored var sendMessageTask: Task<Void, Never>?

    let linkPreviewComposer: TelegramLinkPreviewComposer
    let editLinkPreviewComposer: TelegramLinkPreviewComposer

    var text: AttributedString = "" {
        didSet { linkPreviewComposer.update(text: formattedText(from: text)) }
    }

    var editMessageText: AttributedString = "" {
        didSet { editLinkPreviewComposer.update(text: formattedText(from: editMessageText)) }
    }

    var activeLinkPreviewComposer: TelegramLinkPreviewComposer {
        editCustomMessage == nil ? linkPreviewComposer : editLinkPreviewComposer
    }

    var canEditMessage: Bool {
        guard let editCustomMessage else { return false }
        switch editCustomMessage.message.content {
        case .messageAudio, .messageDocument, .messagePhoto, .messageVideo, .messageVoiceNote:
            return true
        case .messageText:
            return !editMessageText.characters.isEmpty
        default:
            return false
        }
    }

    func sendMessage(schedulingState: MessageSchedulingState? = nil) async throws {
        let wasEditing = editCustomMessage != nil
        let submitted: Bool
        if !displayedDocuments.isEmpty {
            try await sendMessageDocuments(schedulingState: schedulingState)
            submitted = true
        } else if !displayedImages.isEmpty {
            try await sendMessagePhotos(schedulingState: schedulingState)
            submitted = true
        } else if canEditMessage {
            submitted = try await editMessage()
        } else if !text.characters.isEmpty {
            try await sendMessageText(schedulingState: schedulingState)
            submitted = true
        } else {
            return
        }

        guard submitted else { return }
        await main {
            withAnimation {
                if wasEditing {
                    self.editMessageText = ""
                    self.editCustomMessage = nil
                } else {
                    self.displayedImages.removeAll()
                    self.displayedDocuments.removeAll()
                    self.text = ""
                    self.replyMessage = nil
                }
            }
        }
        await updateDraft()
    }

    @MainActor func stageDocuments(_ urls: [URL]) async throws {
        var stagedURLs = [URL]()
        stagedURLs.reserveCapacity(urls.count)
        do {
            for sourceURL in urls {
                let stagedURL = try await TelegramOutgoingFileStaging.shared.stageDocument(
                    sourceURL: sourceURL,
                    suggestedFileName: sourceURL.lastPathComponent,
                    identifier: UUID().uuidString,
                )
                stagedURLs.append(stagedURL)
            }
        } catch {
            for stagedURL in stagedURLs {
                TelegramOutgoingFileStaging.shared.discard(fileURL: stagedURL)
            }
            throw error
        }
        discardDisplayedDocuments()
        discardDisplayedImages()
        displayedDocuments = stagedURLs
        setShowSendButton()
    }

    /// Unlike `stageDocuments(_:)`, adds to whatever's already staged instead of replacing it - for
    /// picking more files from the attachment review screen, where the existing selection must
    /// survive.
    @MainActor func appendStagedDocuments(_ urls: [URL]) async throws {
        var stagedURLs = [URL]()
        stagedURLs.reserveCapacity(urls.count)
        do {
            for sourceURL in urls {
                let stagedURL = try await TelegramOutgoingFileStaging.shared.stageDocument(
                    sourceURL: sourceURL,
                    suggestedFileName: sourceURL.lastPathComponent,
                    identifier: UUID().uuidString,
                )
                stagedURLs.append(stagedURL)
            }
        } catch {
            for stagedURL in stagedURLs {
                TelegramOutgoingFileStaging.shared.discard(fileURL: stagedURL)
            }
            throw error
        }
        displayedDocuments.append(contentsOf: stagedURLs)
        setShowSendButton()
    }

    func discardDisplayedDocuments() {
        for url in displayedDocuments {
            TelegramOutgoingFileStaging.shared.discard(fileURL: url)
        }
        displayedDocuments.removeAll()
    }

    func discardDisplayedImages() {
        for image in displayedImages {
            TelegramOutgoingFileStaging.shared.discard(fileURL: image.url)
        }
        displayedImages.removeAll()
    }

    func sendMessageDocuments(schedulingState: MessageSchedulingState? = nil) async throws {
        let documentURLs = displayedDocuments
        let caption = await TelegramTextFormatting.addingAutomaticEntities(
            service: service,
            to: FormattedText(entities: getEntities(from: text), text: text.string),
        )
        let contents = documentURLs.map { url in
            TelegramMessageSending.documentContent(url: url, caption: caption)
        }
        try await TelegramMessageSending.send(
            service: service,
            chatId: chatId,
            contents: contents,
            replyTo: getMessageReplyTo(from: replyMessage),
            uploadAction: .chatActionUploadingDocument(.init(progress: 0)),
            schedulingState: schedulingState,
            topicId: topicId,
            onAccepted: { [chatId] messages in
                TelegramOutgoingFileStaging.shared.register(
                    fileURLs: documentURLs,
                    chatId: chatId,
                    temporaryMessageIds: messages.map(\.id),
                )
            },
        )
    }

    func sendMessagePhotos(schedulingState: MessageSchedulingState? = nil) async throws {
        let imageURLs = displayedImages.map(\.url)
        let caption = await TelegramTextFormatting.addingAutomaticEntities(
            service: service,
            to: FormattedText(entities: getEntities(from: text), text: text.string),
        )
        let contents = displayedImages.map { makeInputMessageContent(for: $0.url, caption: caption) }
        try await TelegramMessageSending.send(
            service: service,
            chatId: chatId,
            contents: contents,
            replyTo: getMessageReplyTo(from: replyMessage),
            uploadAction: .chatActionUploadingPhoto(.init(progress: 0)),
            schedulingState: schedulingState,
            topicId: topicId,
            onAccepted: { [chatId] messages in
                TelegramOutgoingFileStaging.shared.register(
                    fileURLs: imageURLs,
                    chatId: chatId,
                    temporaryMessageIds: messages.map(\.id),
                )
            },
        )
    }

    func makeInputMessageContent(for url: URL, caption: FormattedText) -> InputMessageContent {
        let pixelSize = imagePixelSize(at: url) ?? .zero
        return TelegramMessageSending.photoContent(
            url: url,
            caption: caption,
            width: Int(pixelSize.width),
            height: Int(pixelSize.height),
        )
    }

    func sendMessageText(schedulingState: MessageSchedulingState? = nil) async throws {
        let formattedText = await TelegramTextFormatting.addingAutomaticEntities(
            service: service,
            to: FormattedText(entities: getEntities(from: text), text: text.string),
        )
        let content = TelegramMessageSending.textContent(
            formattedText,
            linkPreviewOptions: linkPreviewComposer.options,
        )
        try await TelegramMessageSending.send(
            service: service,
            chatId: chatId,
            contents: [content],
            replyTo: getMessageReplyTo(from: replyMessage),
            schedulingState: schedulingState,
            topicId: topicId,
        )
    }

    func editMessage() async throws -> Bool {
        guard let message = editCustomMessage?.message else { return false }
        let newText = await TelegramTextFormatting.addingAutomaticEntities(
            service: service,
            to: formattedText(from: editMessageText),
        )
        let supported = try await TelegramMessageEditing.editMessage(
            service: service,
            chatId: chatId,
            messageId: message.id,
            messageContent: message.content,
            newText: newText,
            linkPreviewOptions: editLinkPreviewComposer.options,
        )
        if !supported {
            log("Unsupported edit message type")
        }
        return supported
    }

    func sendMessageVoiceNote(
        url: URL,
        duration: Int,
        waveform: Data,
        isViewOnce: Bool = false,
        schedulingState: MessageSchedulingState? = nil,
    ) async throws {
        try await TelegramVoiceNoteSending.send(
            service: service,
            chatId: chatId,
            url: url,
            caption: FormattedText(
                entities: getEntities(from: text),
                text: text.string,
            ),
            duration: duration,
            waveform: waveform,
            isViewOnce: isViewOnce,
            replyTo: getMessageReplyTo(from: replyMessage),
            schedulingState: schedulingState,
            topicId: topicId,
        )
        await main {
            self.text = ""
            self.replyMessage = nil
        }
        await updateDraft()
    }

    func sendMessageVideoNote(
        artifact: TelegramVideoNoteRecordingArtifact,
        schedulingState: MessageSchedulingState? = nil,
    ) async throws {
        try await TelegramVideoNoteSending.send(
            service: service,
            chatId: chatId,
            url: artifact.url,
            duration: artifact.duration,
            length: artifact.length,
            isViewOnce: artifact.isViewOnce,
            replyTo: getMessageReplyTo(from: replyMessage),
            schedulingState: schedulingState,
            topicId: topicId,
        )
        await main {
            self.replyMessage = nil
        }
        await updateDraft()
    }

    func updateDraft() async {
        let draftMessage = TelegramDrafts.make(
            formattedText: FormattedText(
                entities: getEntities(from: text),
                text: text.string,
            ),
            replyMessageId: replyMessage?.id,
            linkPreviewOptions: linkPreviewComposer.options,
        )
        _ = try? await service.setChatDraftMessage(
            chatId: chatId,
            draftMessage: draftMessage,
            topicId: topicId,
        )
    }

    func setShowSendButton() {
        guard editCustomMessage == nil else { return withAnimation { showSendButton = true } }
        let value = !displayedDocuments.isEmpty || !displayedImages.isEmpty
            || !editMessageText.characters.isEmpty || !text.characters.isEmpty
        withAnimation { showSendButton = value }
    }

    func setEditMessageText(from message: Message?) {
        withAnimation {
            guard let message, let formattedText = TelegramMessageEditing.editableFormattedText(from: message)
            else {
                editLinkPreviewComposer.configure(preview: nil, options: nil)
                return
            }
            editLinkPreviewComposer.configure(
                preview: telegramMessageLinkPreview(message),
                options: telegramMessageLinkPreviewOptions(message),
            )
            editMessageText = getAttributedString(from: formattedText, linkStyle: .composer)
        }
    }

    // MARK: Private

    private let chatId: Int64
    private let service: any TelegramService
    private let topicId: MessageTopic?

    private func formattedText(from attributedString: AttributedString) -> FormattedText {
        FormattedText(
            entities: getEntities(from: attributedString),
            text: attributedString.string,
        )
    }

    private func getMessageReplyTo(from customMessage: CustomMessage?) -> InputMessageReplyTo? {
        TelegramMessageSending.replyTo(messageId: customMessage?.message.id)
    }
}
