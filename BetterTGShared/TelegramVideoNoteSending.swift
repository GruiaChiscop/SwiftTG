// TelegramVideoNoteSending.swift

import Foundation
import TDLibKit

enum TelegramVideoNoteSending {
    static func content(
        url: URL,
        duration: Int,
        length: Int = 480,
        isViewOnce: Bool = false,
    ) -> InputMessageContent {
        .inputMessageVideoNote(.init(
            selfDestructType: isViewOnce ? .messageSelfDestructTypeImmediately : nil,
            videoNote: InputVideoNote(
                duration: min(max(1, duration), 60),
                length: min(max(1, length), 640),
                thumbnail: nil,
                videoNote: .inputFileLocal(.init(path: TelegramMessageSending.localFilePath(url))),
            ),
        ))
    }

    static func send(
        service: any TelegramService,
        chatId: Int64,
        url: URL,
        duration: Int,
        length: Int = 480,
        isViewOnce: Bool = false,
        replyTo: InputMessageReplyTo?,
        schedulingState: MessageSchedulingState? = nil,
        topicId: MessageTopic? = nil,
    ) async throws {
        do {
            let messages = try await TelegramMessageSending.send(
                service: service,
                chatId: chatId,
                contents: [content(
                    url: url,
                    duration: duration,
                    length: length,
                    isViewOnce: isViewOnce,
                )],
                replyTo: replyTo,
                uploadAction: .chatActionUploadingVideoNote(.init(progress: 0)),
                schedulingState: schedulingState,
                topicId: topicId,
                onAccepted: { messages in
                    guard let message = messages.first else { return }
                    TelegramOutgoingFileStaging.shared.register(
                        fileURL: url,
                        chatId: chatId,
                        temporaryMessageId: message.id,
                    )
                },
            )
            if messages.isEmpty {
                TelegramOutgoingFileStaging.shared.discard(fileURL: url)
            }
        } catch {
            TelegramOutgoingFileStaging.shared.discard(fileURL: url)
            throw error
        }
    }
}
