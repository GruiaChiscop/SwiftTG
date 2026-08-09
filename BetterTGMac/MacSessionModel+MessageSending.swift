// MacSessionModel+MessageSending.swift

import AppKit
import TDLibKit

extension MacSessionModel {
    // MARK: Internal (called from `submitComposer()` in `+ComposerInput.swift`, a different file)

    func sendTextMessage(schedulingState: MessageSchedulingState? = nil) {
        let text = macComposerFormattedText(messageText, trimmingWhitespace: true)
        guard let openedChatId, !text.text.isEmpty else { return }
        let replyTo = TelegramMessageSending.replyTo(messageId: replyingToMessage?.id)
        let replyMessageId = replyingToMessage?.id
        let linkPreviewOptions = linkPreviewComposer.options
        let topicId = openedTopic
        messageActionError = nil
        isSubmittingMessage = true
        Task {
            defer { isSubmittingMessage = false }
            do {
                let formattedText = await TelegramTextFormatting.addingAutomaticEntities(
                    service: service,
                    to: text,
                )
                try await TelegramMessageSending.send(
                    service: service,
                    chatId: openedChatId,
                    contents: [TelegramMessageSending.textContent(
                        formattedText,
                        linkPreviewOptions: linkPreviewOptions,
                    )],
                    replyTo: replyTo,
                    schedulingState: schedulingState,
                    topicId: topicId,
                )
                clearDraft(chatId: openedChatId)
                guard self.openedChatId == openedChatId else { return }
                messageText = NSAttributedString(string: "")
                if replyingToMessage?.id == replyMessageId {
                    replyingToMessage = nil
                }
            } catch {
                guard !Task.isCancelled else { return }
                messageActionError = "Message couldn't be sent: \(telegramErrorDescription(error))"
            }
        }
    }

    func sendSelectedPhotos(schedulingState: MessageSchedulingState? = nil) {
        guard let chatId = openedChatId, !selectedPhotoURLs.isEmpty else { return }
        let urls = selectedPhotoURLs
        let caption = macComposerFormattedText(messageText, trimmingWhitespace: true)
        let replyTo = TelegramMessageSending.replyTo(messageId: replyingToMessage?.id)
        let replyMessageId = replyingToMessage?.id
        let topicId = openedTopic
        let photos = urls.compactMap { url -> (URL, CGSize)? in
            guard let size = imagePixelSize(at: url), size.width > 0, size.height > 0 else { return nil }
            return (url, size)
        }
        guard !photos.isEmpty else {
            messageActionError = "The selected files could not be read as photos."
            return
        }

        messageActionError = nil
        isSubmittingMessage = true
        Task {
            defer { isSubmittingMessage = false }
            do {
                let formattedCaption = await TelegramTextFormatting.addingAutomaticEntities(
                    service: service,
                    to: caption,
                )
                let contents = photos.map { url, size in
                    TelegramMessageSending.photoContent(
                        url: url,
                        caption: formattedCaption,
                        width: Int(size.width),
                        height: Int(size.height),
                    )
                }
                try await TelegramMessageSending.send(
                    service: service,
                    chatId: chatId,
                    contents: contents,
                    replyTo: replyTo,
                    uploadAction: .chatActionUploadingPhoto(.init(progress: 0)),
                    schedulingState: schedulingState,
                    topicId: topicId,
                )
                clearDraft(chatId: chatId)
                guard openedChatId == chatId else { return }
                selectedPhotoURLs = []
                messageText = NSAttributedString(string: "")
                if replyingToMessage?.id == replyMessageId {
                    replyingToMessage = nil
                }
            } catch {
                guard !Task.isCancelled else { return }
                messageActionError = "Message couldn't be sent: \(telegramErrorDescription(error))"
            }
        }
    }

    func sendSelectedDocuments(schedulingState: MessageSchedulingState? = nil) {
        guard let chatId = openedChatId, !selectedDocumentURLs.isEmpty else { return }
        let caption = macComposerFormattedText(messageText, trimmingWhitespace: true)
        let replyTo = TelegramMessageSending.replyTo(messageId: replyingToMessage?.id)
        let replyMessageId = replyingToMessage?.id
        let topicId = openedTopic
        let urls = selectedDocumentURLs

        messageActionError = nil
        isSubmittingMessage = true
        Task {
            defer { isSubmittingMessage = false }
            var stagedURLs = [URL]()
            do {
                let formattedCaption = await TelegramTextFormatting.addingAutomaticEntities(
                    service: service,
                    to: caption,
                )
                stagedURLs.reserveCapacity(urls.count)
                for url in urls {
                    let stagedURL = try await TelegramOutgoingFileStaging.shared.stageDocument(
                        sourceURL: url,
                        suggestedFileName: url.lastPathComponent,
                        identifier: UUID().uuidString,
                    )
                    stagedURLs.append(stagedURL)
                }
                let stagedURLs = stagedURLs
                let contents = stagedURLs.map { url in
                    TelegramMessageSending.documentContent(url: url, caption: formattedCaption)
                }
                try await TelegramMessageSending.send(
                    service: service,
                    chatId: chatId,
                    contents: contents,
                    replyTo: replyTo,
                    uploadAction: .chatActionUploadingDocument(.init(progress: 0)),
                    schedulingState: schedulingState,
                    topicId: topicId,
                    onAccepted: { messages in
                        TelegramOutgoingFileStaging.shared.register(
                            fileURLs: stagedURLs,
                            chatId: chatId,
                            temporaryMessageIds: messages.map(\.id),
                        )
                    },
                )
                clearDraft(chatId: chatId)
                guard openedChatId == chatId else { return }
                selectedDocumentURLs = []
                messageText = NSAttributedString(string: "")
                if replyingToMessage?.id == replyMessageId {
                    replyingToMessage = nil
                }
            } catch {
                for stagedURL in stagedURLs {
                    TelegramOutgoingFileStaging.shared.discard(fileURL: stagedURL)
                }
                guard !Task.isCancelled else { return }
                messageActionError = "Message couldn't be sent: \(telegramErrorDescription(error))"
            }
        }
    }

    func editMessage() {
        guard let message = editingMessage else { return }
        let text = macComposerFormattedText(editMessageText, trimmingWhitespace: true)
        if case .messageText = message.content, text.text.isEmpty {
            return
        }
        let linkPreviewOptions = editLinkPreviewComposer.options
        messageActionError = nil
        isSubmittingMessage = true
        Task {
            defer { isSubmittingMessage = false }
            do {
                let supported = try await TelegramMessageEditing.editMessage(
                    service: service,
                    chatId: message.chatId,
                    messageId: message.id,
                    messageContent: message.content,
                    newText: text,
                    linkPreviewOptions: linkPreviewOptions,
                )
                guard supported else {
                    messageActionError = "This type of message can't be edited."
                    return
                }
                guard openedChatId == message.chatId, editingMessage?.id == message.id else { return }
                editingMessage = nil
                editMessageText = NSAttributedString(string: "")
            } catch {
                guard !Task.isCancelled else { return }
                messageActionError = "Message couldn't be updated: \(telegramErrorDescription(error))"
            }
        }
    }
}
