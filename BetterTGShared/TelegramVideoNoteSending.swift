// TelegramVideoNoteSending.swift

import Foundation
import TDLibKit

enum TelegramVideoNoteSending {
    static func content(
        url: URL,
        thumbnail: TelegramVideoNoteThumbnail? = nil,
        preliminaryUploadFileId: Int? = nil,
        duration: Int,
        length: Int = 480,
        isViewOnce: Bool = false,
    ) -> InputMessageContent {
        .inputMessageVideoNote(.init(
            selfDestructType: isViewOnce ? .messageSelfDestructTypeImmediately : nil,
            videoNote: InputVideoNote(
                duration: min(max(1, duration), 60),
                length: min(max(1, length), 640),
                thumbnail: thumbnail.map { thumbnail in
                    InputThumbnail(
                        height: thumbnail.height,
                        thumbnail: .inputFileLocal(.init(
                            path: TelegramMessageSending.localFilePath(thumbnail.url),
                        )),
                        width: thumbnail.width,
                    )
                },
                videoNote: preliminaryUploadFileId.map { .inputFileId(.init(id: $0)) }
                    ?? .inputFileLocal(.init(path: TelegramMessageSending.localFilePath(url))),
            ),
        ))
    }

    static func send(
        service: any TelegramService,
        chatId: Int64,
        url: URL,
        thumbnail: TelegramVideoNoteThumbnail? = nil,
        preliminaryUploadFileId: Int? = nil,
        duration: Int,
        length: Int = 480,
        isViewOnce: Bool = false,
        replyTo: InputMessageReplyTo?,
        schedulingState: MessageSchedulingState? = nil,
        disableNotification: Bool = false,
        effectId: TdInt64 = 0,
        topicId: MessageTopic? = nil,
    ) async throws {
        do {
            let messages = try await TelegramMessageSending.send(
                service: service,
                chatId: chatId,
                contents: [content(
                    url: url,
                    thumbnail: thumbnail,
                    preliminaryUploadFileId: preliminaryUploadFileId,
                    duration: duration,
                    length: length,
                    isViewOnce: isViewOnce,
                )],
                replyTo: replyTo,
                uploadAction: .chatActionUploadingVideoNote(.init(progress: 0)),
                schedulingState: schedulingState,
                disableNotification: disableNotification,
                effectId: effectId,
                topicId: topicId,
                onAccepted: { messages in
                    guard let message = messages.first else { return }
                    TelegramOutgoingFileStaging.shared.register(
                        fileURLs: [url] + [thumbnail?.url].compactMap(\.self),
                        chatId: chatId,
                        temporaryMessageId: message.id,
                        // TDLib's successful-send update can keep referencing the upload source
                        // for the rest of this process. Removing it immediately makes a freshly
                        // sent video note unplayable until the conversation is reloaded.
                        successfulSendCleanup: .retainUntilStale,
                    )
                },
            )
            if messages.isEmpty {
                if let preliminaryUploadFileId {
                    _ = try? await service.cancelPreliminaryUploadFile(fileId: preliminaryUploadFileId)
                }
                TelegramOutgoingFileStaging.shared.discard(fileURL: url)
                if let thumbnail {
                    TelegramOutgoingFileStaging.shared.discard(fileURL: thumbnail.url)
                }
            }
        } catch {
            if let preliminaryUploadFileId {
                _ = try? await service.cancelPreliminaryUploadFile(fileId: preliminaryUploadFileId)
            }
            TelegramOutgoingFileStaging.shared.discard(fileURL: url)
            if let thumbnail {
                TelegramOutgoingFileStaging.shared.discard(fileURL: thumbnail.url)
            }
            throw error
        }
    }
}
