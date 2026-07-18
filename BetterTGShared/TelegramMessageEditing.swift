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
    @discardableResult static func editMessage(
        service: any TelegramService,
        chatId: Int64,
        messageId: Int64,
        messageContent: MessageContent,
        newText: FormattedText,
    ) async -> Bool {
        let newText = await TelegramTextFormatting.addingAutomaticEntities(service: service, to: newText)
        switch messageContent {
        case .messageText:
            _ = try? await service.editMessageText(
                chatId: chatId,
                inputMessageContent: .inputMessageText(.init(
                    clearDraft: true,
                    linkPreviewOptions: nil,
                    text: newText,
                )),
                messageId: messageId,
                replyMarkup: nil,
            )
            return true
        case .messageAudio, .messageDocument, .messagePhoto, .messageVideo, .messageVoiceNote:
            _ = try? await service.editMessageCaption(
                caption: newText,
                chatId: chatId,
                messageId: messageId,
                replyMarkup: nil,
                showCaptionAboveMedia: false,
            )
            return true
        default:
            return false
        }
    }
}
