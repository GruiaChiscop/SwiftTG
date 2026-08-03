// TelegramMessageAlbum.swift

import TDLibKit

// MARK: - TelegramMessageAlbumGroup

struct TelegramMessageAlbumGroup: Equatable {
    let representativeMessageId: Int64
    let mediaAlbumId: TdInt64?
    var messageIds: [Int64]

    var isAlbum: Bool { mediaAlbumId != nil }
}

func telegramMediaAlbumAccessibilityDescription(itemCount: Int) -> String {
    "Album with \(itemCount) \(itemCount == 1 ? "item" : "items")"
}

/// Collapses photo and video messages that share a Telegram media album identifier while keeping
/// every other message in its original position. Document and audio batches intentionally remain
/// separate rows because they don't use the visual album presentation.
func telegramVisualMessageAlbumGroups(
    orderedMessageIds: [Int64],
    messages: [Int64: Message],
) -> [TelegramMessageAlbumGroup] {
    var groups = [TelegramMessageAlbumGroup]()
    var albumIndexes = [TdInt64: Int]()

    for messageId in orderedMessageIds {
        guard let message = messages[messageId] else { continue }
        let albumId = message.mediaAlbumId
        guard albumId != 0, telegramMessageSupportsVisualAlbum(message) else {
            groups.append(.init(
                representativeMessageId: messageId,
                mediaAlbumId: nil,
                messageIds: [messageId],
            ))
            continue
        }

        if let groupIndex = albumIndexes[albumId] {
            groups[groupIndex].messageIds.append(messageId)
        } else {
            albumIndexes[albumId] = groups.count
            groups.append(.init(
                representativeMessageId: messageId,
                mediaAlbumId: albumId,
                messageIds: [messageId],
            ))
        }
    }

    return groups
}

func telegramVisualMessageAlbumRepresentativeId(
    for messageId: Int64,
    orderedMessageIds: [Int64],
    messages: [Int64: Message],
) -> Int64 {
    telegramVisualMessageAlbumGroups(
        orderedMessageIds: orderedMessageIds,
        messages: messages,
    )
    .first(where: { $0.messageIds.contains(messageId) })?
    .representativeMessageId ?? messageId
}

func telegramMessageSupportsVisualAlbum(_ message: Message) -> Bool {
    switch message.content {
    case .messagePhoto, .messageVideo:
        true
    default:
        false
    }
}
