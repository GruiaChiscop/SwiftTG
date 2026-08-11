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
        output: TelegramStickerEditorOutput,
        emojis: String,
        service: any TelegramService,
        chatId: Int64,
        topicId: MessageTopic?,
    ) async throws {
        let uploaded = try await upload(output: output, emojis: emojis, service: service)
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
        output: TelegramStickerEditorOutput,
        emojis: String,
        service: any TelegramService,
    ) async throws {
        let uploaded = try await upload(output: output, emojis: emojis, service: service)
        _ = try await service.replaceStickerInSet(
            name: packName,
            newSticker: uploaded.newSticker,
            oldSticker: .inputFileId(.init(id: original.sticker.id)),
            userId: nil,
        )
    }

    // MARK: Private

    private static func upload(
        output: TelegramStickerEditorOutput,
        emojis: String,
        service: any TelegramService,
    ) async throws -> (file: File, newSticker: NewSticker, width: Int, height: Int) {
        let prepared = try preparedUpload(output)
        defer {
            if prepared.removesFileAfterUpload {
                try? FileManager.default.removeItem(at: prepared.fileURL)
            }
        }

        let file = try await service.uploadStickerFile(
            sticker: .inputFileLocal(.init(path: prepared.fileURL.path)),
            stickerFormat: prepared.format,
            userId: nil,
        )
        let newSticker = NewSticker(
            emojis: emojis,
            format: prepared.format,
            keywords: [],
            maskPosition: nil,
            sticker: .inputFileId(.init(id: file.id)),
        )
        return (file, newSticker, prepared.width, prepared.height)
    }

    private static func preparedUpload(
        _ output: TelegramStickerEditorOutput,
    ) throws -> (fileURL: URL, format: StickerFormat, height: Int, width: Int, removesFileAfterUpload: Bool) {
        switch output {
        case .image(let pngData):
            guard let source = CGImageSourceCreateWithData(pngData as CFData, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
                  let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue
            else {
                throw TelegramStickerEditorError.imageDecodingFailed
            }
            let fileURL = URL.temporaryDirectory
                .appending(path: "bettertg-edited-sticker-\(UUID().uuidString)")
                .appendingPathExtension("png")
            try pngData.write(to: fileURL)
            return (fileURL, output.format, height, width, true)
        case .video(let fileURL, let width, let height, _):
            return (fileURL, output.format, height, width, false)
        }
    }
}
