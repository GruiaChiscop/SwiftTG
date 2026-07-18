// TelegramMessageSending.swift

import Foundation
import TDLibKit

enum TelegramMessageSending {
    // MARK: Internal

    static func replyTo(messageId: Int64?) -> InputMessageReplyTo? {
        guard let messageId else { return nil }
        return .inputMessageReplyToMessage(.init(
            checklistTaskId: 0,
            messageId: messageId,
            pollOptionId: "",
            quote: nil,
        ))
    }

    static func textContent(_ text: FormattedText) -> InputMessageContent {
        .inputMessageText(.init(
            clearDraft: true,
            linkPreviewOptions: nil,
            text: text,
        ))
    }

    static func documentContent(url: URL, caption: FormattedText) -> InputMessageContent {
        .inputMessageDocument(.init(
            caption: caption,
            document: InputDocument(
                disableContentTypeDetection: true,
                document: .inputFileLocal(.init(path: url.path())),
                thumbnail: nil,
            ),
        ))
    }

    static func photoContent(
        url: URL,
        caption: FormattedText,
        width: Int,
        height: Int,
    ) -> InputMessageContent {
        .inputMessagePhoto(.init(
            caption: caption,
            hasSpoiler: false,
            photo: InputPhoto(
                addedStickerFileIds: [],
                height: height,
                photo: .inputFileLocal(.init(path: url.path())),
                thumbnail: nil,
                video: nil,
                width: width,
            ),
            selfDestructType: nil,
            showCaptionAboveMedia: false,
        ))
    }

    @discardableResult static func send(
        service: any TelegramService,
        chatId: Int64,
        contents: [InputMessageContent],
        replyTo: InputMessageReplyTo?,
        uploadAction: ChatAction? = nil,
        onAccepted: (([Message]) -> Void)? = nil,
    ) async throws -> [Message] {
        guard !contents.isEmpty else { return [] }
        if let uploadAction {
            _ = try? await service.sendChatAction(
                action: uploadAction,
                businessConnectionId: nil,
                chatId: chatId,
                topicId: nil,
            )
        }
        do {
            // swiftformat:disable:next conditionalAssignment
            if contents.count == 1, let content = contents.first {
                let message = try await service.sendMessage(
                    chatId: chatId,
                    inputMessageContent: content,
                    options: nil,
                    replyMarkup: nil,
                    replyTo: replyTo,
                    topicId: nil,
                )
                onAccepted?([message])
                await cancelChatAction(service: service, chatId: chatId)
                return [message]
            } else {
                let messages = try await service.sendMessageAlbum(
                    chatId: chatId,
                    inputMessageContents: contents,
                    options: nil,
                    replyTo: replyTo,
                    topicId: nil,
                )
                onAccepted?(messages.messages ?? [])
                await cancelChatAction(service: service, chatId: chatId)
                return messages.messages ?? []
            }
        } catch {
            await cancelChatAction(service: service, chatId: chatId)
            throw error
        }
    }

    // MARK: Private

    private static func cancelChatAction(service: any TelegramService, chatId: Int64) async {
        _ = try? await service.sendChatAction(
            action: .chatActionCancel,
            businessConnectionId: nil,
            chatId: chatId,
            topicId: nil,
        )
    }
}
