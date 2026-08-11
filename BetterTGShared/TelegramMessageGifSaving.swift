// TelegramMessageGifSaving.swift

import TDLibKit

enum TelegramMessageGifSaving {
    static func fileID(from message: Message) -> Int? {
        guard message.canBeSaved else { return nil }

        switch message.content {
        case .messageAnimation(let content):
            return content.animation.animation.id
        case .messageText(let content):
            guard let preview = content.linkPreview,
                  case .linkPreviewTypeAnimation(let animationPreview) = preview.type
            else { return nil }
            return animationPreview.animation.animation.id
        default:
            return nil
        }
    }

    static func save(
        fileID: Int,
        service: any TelegramService,
    ) async throws {
        _ = try await service.addSavedAnimation(
            animation: .inputFileId(.init(id: fileID)),
        )
    }
}
