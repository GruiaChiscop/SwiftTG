// TelegramDrafts.swift

import Foundation
import TDLibKit

enum TelegramDrafts {
    static func make(text: String, replyMessageId: Int64?, date: Foundation.Date = .now) -> DraftMessage? {
        make(
            formattedText: FormattedText(entities: [], text: text),
            replyMessageId: replyMessageId,
            date: date,
        )
    }

    static func make(
        formattedText: FormattedText,
        replyMessageId: Int64?,
        linkPreviewOptions: LinkPreviewOptions? = nil,
        date: Foundation.Date = .now,
    ) -> DraftMessage? {
        guard !formattedText.text.isEmpty || replyMessageId != nil else { return nil }
        return DraftMessage(
            content: .draftMessageContentText(
                DraftMessageContentText(
                    linkPreviewOptions: linkPreviewOptions,
                    text: formattedText,
                ),
            ),
            date: Int(date.timeIntervalSince1970),
            effectId: 0,
            replyTo: TelegramMessageSending.replyTo(messageId: replyMessageId),
            suggestedPostInfo: nil,
        )
    }

    static func text(from draft: DraftMessage?) -> String {
        guard let draft,
              case .draftMessageContentText(let content) = draft.content
        else { return "" }
        return content.text.text
    }

    static func replyMessageId(from draft: DraftMessage?) -> Int64? {
        guard let draft,
              case .inputMessageReplyToMessage(let reply) = draft.replyTo
        else { return nil }
        return reply.messageId == 0 ? nil : reply.messageId
    }
}
