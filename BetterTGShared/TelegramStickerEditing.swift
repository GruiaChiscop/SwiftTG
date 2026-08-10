// TelegramStickerEditing.swift

import Foundation
import ImageIO
import TDLibKit

enum TelegramStickerEditing {
    // MARK: Internal

    static func messageContent(
        fileId: Int,
        emojis: String,
        height: Int,
        width: Int,
    ) -> InputMessageContent {
        .inputMessageSticker(.init(
            emoji: emojis,
            sticker: .init(
                height: height,
                sticker: .inputFileId(.init(id: fileId)),
                thumbnail: nil,
                width: width,
            ),
        ))
    }

    static func sendEditedSticker(
        pngData: Data,
        emojis: String,
        service: any TelegramService,
        chatId: Int64,
        topicId: MessageTopic?,
    ) async throws {
        let uploaded = try await upload(pngData: pngData, emojis: emojis, service: service)
        try await TelegramMessageSending.send(
            service: service,
            chatId: chatId,
            contents: [messageContent(
                fileId: uploaded.file.id,
                emojis: emojis,
                height: uploaded.height,
                width: uploaded.width,
            )],
            replyTo: nil,
            topicId: topicId,
            onAccepted: { messages in
                service.mergeMessages(chatId: chatId, messages: messages)
            },
        )
    }

    static func replaceSticker(
        _ original: Sticker,
        inPackNamed packName: String,
        pngData: Data,
        emojis: String,
        service: any TelegramService,
    ) async throws {
        let uploaded = try await upload(pngData: pngData, emojis: emojis, service: service)
        _ = try await service.replaceStickerInSet(
            name: packName,
            newSticker: uploaded.newSticker,
            oldSticker: .inputFileId(.init(id: original.sticker.id)),
            userId: nil,
        )
    }

    // MARK: Private

    private static func upload(
        pngData: Data,
        emojis: String,
        service: any TelegramService,
    ) async throws -> (file: File, newSticker: NewSticker, width: Int, height: Int) {
        guard let source = CGImageSourceCreateWithData(pngData as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue
        else {
            throw TelegramStickerEditorError.imageDecodingFailed
        }

        let fileURL = URL.temporaryDirectory.appending(path: "bettertg-edited-sticker-\(UUID().uuidString).png")
        try pngData.write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let file = try await service.uploadStickerFile(
            sticker: .inputFileLocal(.init(path: fileURL.path)),
            stickerFormat: .stickerFormatWebp,
            userId: nil,
        )
        let newSticker = NewSticker(
            emojis: emojis,
            format: .stickerFormatWebp,
            keywords: [],
            maskPosition: nil,
            sticker: .inputFileId(.init(id: file.id)),
        )
        return (file, newSticker, width, height)
    }
}
