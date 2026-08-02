// TelegramMessageEditing.swift

import TDLibKit

/// Message-edit logic shared between ChatVM (iOS) and MacSessionModel (macOS):
/// which content types are editable, and which TDLib call applies to each.
enum TelegramMessageEditing {
    static func editableFormattedText(from message: Message) -> FormattedText? {
        switch message.content {
        case .messageText(let content): content.text
        case .messagePhoto(let content): content.caption
        case .messageVideo(let content): content.caption
        case .messageVoiceNote(let content): content.caption
        case .messageAudio(let content): content.caption
        case .messageDocument(let content): content.caption
        default: nil
        }
    }

    /// Applies `newText` to `messageContent` via the matching TDLib edit call.
    /// Returns `false` without side effects if the content type isn't editable.
    ///
    /// TDLib doesn't push `updateMessageEdited`/`updateMessageContent` back to the client that
    /// made the edit (only to other sessions), so the edit's own client has to notify itself using
    /// the `Message` its own edit call already returned - otherwise the edited content stays stuck
    /// showing the pre-edit text until something else happens to refetch it.
    @discardableResult static func editMessage(
        service: any TelegramService,
        chatId: Int64,
        messageId: Int64,
        messageContent: MessageContent,
        newText: FormattedText,
        linkPreviewOptions: LinkPreviewOptions? = nil,
    ) async throws -> Bool {
        let newText = await TelegramTextFormatting.addingAutomaticEntities(service: service, to: newText)
        let edited = try await performEdit(
            messageContent: messageContent,
            editText: {
                try await service.editMessageText(
                    chatId: chatId,
                    inputMessageContent: .inputMessageText(.init(
                        clearDraft: true,
                        linkPreviewOptions: linkPreviewOptions,
                        text: newText,
                    )),
                    messageId: messageId,
                    replyMarkup: nil,
                )
            },
            editCaption: {
                try await service.editMessageCaption(
                    caption: newText,
                    chatId: chatId,
                    messageId: messageId,
                    replyMarkup: nil,
                    showCaptionAboveMedia: false,
                )
            },
        )
        guard let edited else { return false }
        service.notifyMessageContentChanged(chatId: chatId, messageId: messageId, newContent: edited.content)
        return true
    }

    static func performEdit(
        messageContent: MessageContent,
        editText: () async throws -> Message,
        editCaption: () async throws -> Message,
    ) async throws -> Message? {
        switch messageContent {
        case .messageText:
            try await editText()
        case .messageAudio, .messageDocument, .messagePhoto, .messageVideo, .messageVoiceNote:
            try await editCaption()
        default:
            nil
        }
    }
}
