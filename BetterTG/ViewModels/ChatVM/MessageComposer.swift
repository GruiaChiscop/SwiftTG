// MessageComposer.swift

import SwiftUI
import TDLibKit

/// Staging, editing, and sending of a chat's outgoing text/photo/document/voice-note content.
/// Split out of `ChatVM`, which composes this alongside `VoiceRecordingController` and keeps its
/// own scope to history loading, rendering, and navigation.
@Observable final class MessageComposer {
    // MARK: Lifecycle

    init(chatId: Int64, service: any TelegramService, draftMessage: DraftMessage?) {
        self.chatId = chatId
        self.service = service
        if let draftMessage,
           case .draftMessageContentText(let draftMessageContentText) = draftMessage.content
        {
            self.text = getAttributedString(from: draftMessageContentText.text)
        }
    }

    // MARK: Internal

    var text: AttributedString = ""
    var editMessageText: AttributedString = ""
    var editCustomMessage: CustomMessage?
    var replyMessage: CustomMessage?
    var showSendButton = false
    var showDetail = false
    var displayedImages = [SelectedImage]()
    var displayedDocuments = [URL]()
    var showCameraView = false
    var showDocumentPicker = false
    var showPhotoPickerView = false
    @ObservationIgnored var sendMessageTask: Task<Void, Never>?

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

    func sendMessage() async {
        if !displayedDocuments.isEmpty {
            await sendMessageDocuments()
        } else if !displayedImages.isEmpty {
            await sendMessagePhotos()
        } else if canEditMessage {
            await editMessage()
        } else if !text.characters.isEmpty {
            await sendMessageText()
        } else {
            return
        }

        await main {
            withAnimation {
                self.displayedImages.removeAll()
                self.displayedDocuments.removeAll()
                self.editMessageText = ""
                self.text = ""
                self.replyMessage = nil
                self.editCustomMessage = nil
            }
        }
    }

    func stageDocuments(_ urls: [URL]) async {
        let stagedURLs = await stageAttachmentURLs(urls)
        displayedImages.removeAll()
        displayedDocuments = stagedURLs
        setShowSendButton()
    }

    func sendMessageDocuments() async {
        let caption = await TelegramTextFormatting.addingAutomaticEntities(
            service: service,
            to: FormattedText(entities: getEntities(from: text), text: text.string),
        )
        let contents = displayedDocuments.map { url in
            TelegramMessageSending.documentContent(url: url, caption: caption)
        }
        _ = try? await TelegramMessageSending.send(
            service: service,
            chatId: chatId,
            contents: contents,
            replyTo: getMessageReplyTo(from: replyMessage),
            uploadAction: .chatActionUploadingDocument(.init(progress: 0)),
        )
    }

    func sendMessagePhotos() async {
        let caption = await TelegramTextFormatting.addingAutomaticEntities(
            service: service,
            to: FormattedText(entities: getEntities(from: text), text: text.string),
        )
        let contents = displayedImages.map { makeInputMessageContent(for: $0.url, caption: caption) }
        _ = try? await TelegramMessageSending.send(
            service: service,
            chatId: chatId,
            contents: contents,
            replyTo: getMessageReplyTo(from: replyMessage),
            uploadAction: .chatActionUploadingPhoto(.init(progress: 0)),
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

    func sendMessageText() async {
        let formattedText = await TelegramTextFormatting.addingAutomaticEntities(
            service: service,
            to: FormattedText(entities: getEntities(from: text), text: text.string),
        )
        let content = TelegramMessageSending.textContent(formattedText)
        _ = try? await TelegramMessageSending.send(
            service: service,
            chatId: chatId,
            contents: [content],
            replyTo: getMessageReplyTo(from: replyMessage),
        )
    }

    func editMessage() async {
        guard let message = editCustomMessage?.message else { return }
        let newText = FormattedText(entities: getEntities(from: editMessageText), text: editMessageText.string)
        let supported = await TelegramMessageEditing.editMessage(
            service: service,
            chatId: chatId,
            messageId: message.id,
            messageContent: message.content,
            newText: newText,
        )
        if !supported {
            log("Unsupported edit message type")
        }
    }

    func sendMessageVoiceNote(url: URL, duration: Int, waveform: Data) async {
        try? await TelegramVoiceNoteSending.send(
            service: service,
            chatId: chatId,
            url: url,
            caption: FormattedText(
                entities: getEntities(from: text),
                text: text.string,
            ),
            duration: duration,
            waveform: waveform,
            replyTo: getMessageReplyTo(from: replyMessage),
        )
        text = ""
    }

    func updateDraft() async {
        let draftMessage = DraftMessage(
            content: .draftMessageContentText(
                DraftMessageContentText(
                    linkPreviewOptions: nil,
                    text: FormattedText(
                        entities: getEntities(from: text),
                        text: text.string,
                    ),
                ),
            ),
            date: Int(Date.now.timeIntervalSince1970),
            effectId: 0,
            replyTo: getMessageReplyTo(from: replyMessage),
            suggestedPostInfo: nil,
        )
        _ = try? await service.setChatDraftMessage(
            chatId: chatId,
            draftMessage: draftMessage,
            topicId: nil,
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
            else { return }
            editMessageText = getAttributedString(from: formattedText)
        }
    }

    // MARK: Private

    private let chatId: Int64
    private let service: any TelegramService

    private func getMessageReplyTo(from customMessage: CustomMessage?) -> InputMessageReplyTo? {
        TelegramMessageSending.replyTo(messageId: customMessage?.message.id)
    }

    /// Stages each URL under its own UUID-named subdirectory, rather than folding the UUID into
    /// the file name itself - `documentContent(url:caption:)` uploads using the staged file's own
    /// name, so a `"<uuid>-original.ext"` staging name would send (and permanently store) that
    /// prefixed name as the document's file name instead of the original.
    private func stageAttachmentURLs(_ urls: [URL]) async -> [URL] {
        await Task.detached(priority: .userInitiated) {
            urls.compactMap { source -> URL? in
                let accessed = source.startAccessingSecurityScopedResource()
                defer {
                    if accessed {
                        source.stopAccessingSecurityScopedResource()
                    }
                }
                let destinationDirectory = URL(filePath: NSTemporaryDirectory())
                    .appending(path: UUID().uuidString, directoryHint: .isDirectory)
                let destination = destinationDirectory.appending(path: source.lastPathComponent)
                do {
                    try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
                    try FileManager.default.copyItem(at: source, to: destination)
                    return destination
                } catch {
                    return nil
                }
            }
        }.value
    }
}
