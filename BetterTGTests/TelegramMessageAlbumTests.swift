// TelegramMessageAlbumTests.swift

@testable import BetterTG
import TDLibKit
import Testing

struct TelegramMessageAlbumTests {
    // MARK: Internal

    @Test func `photo album becomes one group at its first message position`() {
        let first = message(id: 1, albumId: 50, content: photoContent())
        let standalone = message(id: 2)
        let second = message(id: 3, albumId: 50, content: photoContent())
        let messages = [first.id: first, standalone.id: standalone, second.id: second]

        let groups = telegramVisualMessageAlbumGroups(
            orderedMessageIds: [first.id, standalone.id, second.id],
            messages: messages,
        )

        #expect(groups.map(\.messageIds) == [[1, 3], [2]])
        #expect(groups[0].representativeMessageId == first.id)
        #expect(groups[0].isAlbum)
    }

    @Test func `nonvisual batches remain individual rows`() {
        let first = message(id: 1, albumId: 60, content: documentContent(fileId: 1))
        let second = message(id: 2, albumId: 60, content: documentContent(fileId: 2))
        let messages = [first.id: first, second.id: second]

        let groups = telegramVisualMessageAlbumGroups(
            orderedMessageIds: [first.id, second.id],
            messages: messages,
        )

        #expect(groups.map(\.messageIds) == [[1], [2]])
        #expect(groups.allSatisfy { !$0.isAlbum })
    }

    @Test func `album member navigation resolves to representative row`() {
        let first = message(id: 10, albumId: 70, content: photoContent())
        let second = message(id: 11, albumId: 70, content: photoContent())
        let messages = [first.id: first, second.id: second]

        #expect(telegramVisualMessageAlbumRepresentativeId(
            for: second.id,
            orderedMessageIds: [first.id, second.id],
            messages: messages,
        ) == first.id)
    }

    @Test func `album accessibility description uses item count`() {
        #expect(telegramMediaAlbumAccessibilityDescription(itemCount: 1) == "Album with 1 item")
        #expect(telegramMediaAlbumAccessibilityDescription(itemCount: 3) == "Album with 3 items")
    }

    @Test func `chat list identifies an album when its item count is unavailable`() {
        let lastMessage = message(id: 20, albumId: 80, content: photoContent())

        #expect(telegramChatListMessageDescription(lastMessage) == "Album")
    }

    @Test func `chat list preserves an album caption`() {
        let lastMessage = message(id: 21, albumId: 80, content: photoContent(caption: "Trip"))

        #expect(telegramChatListMessageDescription(lastMessage) == "Trip")
    }

    // MARK: Private

    private func message(
        id: Int64,
        albumId: TdInt64 = 0,
        content: MessageContent? = nil,
    ) -> Message {
        TDLibFixtures.message(
            id: id,
            chatId: 1,
            date: Int(id),
            mediaAlbumId: albumId,
            content: content,
        )
    }

    private func photoContent(caption: String = "") -> MessageContent {
        .messagePhoto(.init(
            caption: .init(entities: [], text: caption),
            hasSpoiler: false,
            isSecret: false,
            photo: .init(hasStickers: false, minithumbnail: nil, sizes: []),
            showCaptionAboveMedia: false,
            video: nil,
        ))
    }

    private func documentContent(fileId: Int) -> MessageContent {
        .messageDocument(.init(
            caption: .init(entities: [], text: ""),
            document: .init(
                document: TDLibFixtures.file(id: fileId, downloadedSize: 0),
                fileName: "document-\(fileId).pdf",
                mimeType: "application/pdf",
                minithumbnail: nil,
                thumbnail: nil,
            ),
        ))
    }
}
