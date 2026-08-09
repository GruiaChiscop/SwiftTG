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

    static func textContent(
        _ text: FormattedText,
        linkPreviewOptions: LinkPreviewOptions? = nil,
    ) -> InputMessageContent {
        .inputMessageText(.init(
            clearDraft: true,
            linkPreviewOptions: linkPreviewOptions,
            text: text,
        ))
    }

    static func documentContent(url: URL, caption: FormattedText) -> InputMessageContent {
        .inputMessageDocument(.init(
            caption: caption,
            document: InputDocument(
                disableContentTypeDetection: true,
                document: .inputFileLocal(.init(path: localFilePath(url))),
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
                photo: .inputFileLocal(.init(path: localFilePath(url))),
                thumbnail: nil,
                video: nil,
                width: width,
            ),
            selfDestructType: nil,
            showCaptionAboveMedia: false,
        ))
    }

    static func localFilePath(_ url: URL) -> String {
        url.path(percentEncoded: false)
    }

    @discardableResult static func send(
        service: any TelegramService,
        chatId: Int64,
        contents: [InputMessageContent],
        replyTo: InputMessageReplyTo?,
        uploadAction: ChatAction? = nil,
        schedulingState: MessageSchedulingState? = nil,
        topicId: MessageTopic? = nil,
        onAccepted: (@Sendable ([Message]) -> Void)? = nil,
    ) async throws -> [Message] {
        guard !contents.isEmpty else { return [] }
        // A scheduled send has nothing to upload yet from the recipient's perspective, and
        // shouldn't flash a "typing"/"uploading" indicator for a message that isn't being sent now.
        if let uploadAction, schedulingState == nil {
            _ = try? await service.sendChatAction(
                action: uploadAction,
                businessConnectionId: nil,
                chatId: chatId,
                topicId: topicId,
            )
        }
        let options = sendOptions(schedulingState: schedulingState)
        do {
            // swiftformat:disable:next conditionalAssignment
            if contents.count == 1, let content = contents.first {
                let message = try await service.sendMessage(
                    chatId: chatId,
                    inputMessageContent: content,
                    options: options,
                    replyMarkup: nil,
                    replyTo: replyTo,
                    topicId: topicId,
                )
                onAccepted?([message])
                await cancelChatAction(service: service, chatId: chatId, topicId: topicId)
                return [message]
            } else {
                let messages = try await service.sendMessageAlbum(
                    chatId: chatId,
                    inputMessageContents: contents,
                    options: options,
                    replyTo: replyTo,
                    topicId: topicId,
                )
                onAccepted?(messages.messages ?? [])
                await cancelChatAction(service: service, chatId: chatId, topicId: topicId)
                return messages.messages ?? []
            }
        } catch {
            await cancelChatAction(service: service, chatId: chatId, topicId: topicId)
            throw error
        }
    }

    // MARK: Private

    private static func sendOptions(schedulingState: MessageSchedulingState?) -> MessageSendOptions? {
        guard let schedulingState else { return nil }
        return MessageSendOptions(
            allowPaidBroadcast: false,
            disableNotification: false,
            effectId: 0,
            fromBackground: false,
            onlyPreview: false,
            paidMessageStarCount: 0,
            protectContent: false,
            schedulingState: schedulingState,
            sendingId: 0,
            suggestedPostInfo: nil,
            updateOrderOfInstalledStickerSets: false,
        )
    }

    private static func cancelChatAction(
        service: any TelegramService,
        chatId: Int64,
        topicId: MessageTopic? = nil,
    ) async {
        _ = try? await service.sendChatAction(
            action: .chatActionCancel,
            businessConnectionId: nil,
            chatId: chatId,
            topicId: topicId,
        )
    }
}
