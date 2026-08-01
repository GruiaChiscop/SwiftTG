// TelegramLinkPreviewTests.swift

@testable import BetterTG
import Foundation
import TDLibKit
import Testing
import UIKit

struct TelegramLinkPreviewTests {
    // MARK: Internal

    @Test func `presentation preserves textual metadata and normalizes destination`() {
        let preview = makePreview(
            author: "Ada",
            description: "A careful description",
            displayURL: "example.com/article",
            siteName: "Example",
            title: "Article title",
            url: "example.com/article",
        )

        let presentation = TelegramLinkPreviewPresentation(preview)

        #expect(presentation.url?.absoluteString == "https://example.com/article")
        #expect(presentation.siteName == "Example")
        #expect(presentation.title == "Article title")
        #expect(presentation.author == "Ada")
        #expect(presentation.summary == "A careful description")
        #expect(presentation.accessibilityDescription ==
            "Link preview, Example, Article title, Ada, A careful description")
    }

    @Test func `presentation falls back to the destination host for the site name`() {
        let presentation = TelegramLinkPreviewPresentation(makePreview(
            displayURL: "",
            siteName: "",
            url: "https://example.com/path",
        ))

        #expect(presentation.siteName == "example.com")
        #expect(presentation.displayURL == "https://example.com/path")
    }

    @Test func `photo preview chooses the largest available static size`() {
        let small = PhotoSize(
            height: 90,
            photo: TDLibFixtures.file(id: 10, downloadedSize: 0),
            progressiveSizes: [],
            type: "s",
            width: 160,
        )
        let large = PhotoSize(
            height: 720,
            photo: TDLibFixtures.file(id: 11, downloadedSize: 0),
            progressiveSizes: [],
            type: "x",
            width: 1280,
        )
        let photo = Photo(hasStickers: false, minithumbnail: nil, sizes: [small, large])
        let preview = makePreview(type: .linkPreviewTypePhoto(.init(photo: photo)))

        let media = TelegramLinkPreviewPresentation(preview).media

        #expect(media?.fileId == 11)
        #expect(media?.aspectRatio == 1280.0 / 720.0)
    }

    @Test func `photo preview avoids downloading a larger size than the card needs`() {
        let cardSize = PhotoSize(
            height: 600,
            photo: TDLibFixtures.file(id: 20, downloadedSize: 0),
            progressiveSizes: [],
            type: "x",
            width: 800,
        )
        let oversized = PhotoSize(
            height: 1920,
            photo: TDLibFixtures.file(id: 21, downloadedSize: 0),
            progressiveSizes: [],
            type: "w",
            width: 2560,
        )
        let photo = Photo(hasStickers: false, minithumbnail: nil, sizes: [oversized, cardSize])

        let media = TelegramLinkPreviewPresentation(makePreview(
            type: .linkPreviewTypePhoto(.init(photo: photo)),
        )).media

        #expect(media?.fileId == 20)
    }

    @Test func `composer URL detection supports raw and formatted links`() {
        let raw = FormattedText(entities: [], text: "Read https://example.com/article")
        #expect(TelegramLinkPreviewComposer.firstWebURL(in: raw)?.absoluteString ==
            "https://example.com/article")

        let formatted = FormattedText(
            entities: [.init(
                length: 4,
                offset: 0,
                type: .textEntityTypeTextUrl(.init(url: "https://example.org/hidden")),
            )],
            text: "Read",
        )
        #expect(TelegramLinkPreviewComposer.firstWebURL(in: formatted)?.absoluteString ==
            "https://example.org/hidden")
    }

    @Test func `composer prefers edited visible URL over a stale text URL entity`() {
        let editedURL = "https://example.net/edited"
        let text = FormattedText(
            entities: [.init(
                length: editedURL.utf16.count,
                offset: 0,
                type: .textEntityTypeTextUrl(.init(url: "https://example.com/original")),
            )],
            text: editedURL,
        )

        #expect(TelegramLinkPreviewComposer.firstWebURL(in: text)?.absoluteString == editedURL)
    }

    @Test func `composer still prefers an earlier hidden link over a later raw URL`() {
        let text = FormattedText(
            entities: [.init(
                length: 4,
                offset: 0,
                type: .textEntityTypeTextUrl(.init(url: "https://example.org/hidden")),
            )],
            text: "Read https://example.com/later",
        )

        #expect(TelegramLinkPreviewComposer.firstWebURL(in: text)?.absoluteString ==
            "https://example.org/hidden")
    }

    @Test func `composer text keeps links visually plain while preserving explicit destinations`() {
        let rawURL = "https://example.com/raw"
        let raw = FormattedText(
            entities: [.init(length: rawURL.utf16.count, offset: 0, type: .textEntityTypeUrl)],
            text: rawURL,
        )
        let rawAttributes = telegramNSAttributedString(
            from: getAttributedString(from: raw, linkStyle: .composer),
        ).attributes(at: 0, effectiveRange: nil)
        #expect(rawAttributes[.link] == nil)
        #expect(rawAttributes[.underlineStyle] == nil)

        let explicit = FormattedText(
            entities: [.init(
                length: 4,
                offset: 0,
                type: .textEntityTypeTextUrl(.init(url: "https://example.org/hidden")),
            )],
            text: "Read",
        )
        let explicitAttributes = telegramNSAttributedString(
            from: getAttributedString(from: explicit, linkStyle: .composer),
        ).attributes(at: 0, effectiveRange: nil)
        #expect(explicitAttributes[telegramTextURLAttributeKey] as? String == "https://example.org/hidden")
        #expect(explicitAttributes[.link] == nil)
        #expect(explicitAttributes[.underlineStyle] == nil)
        #expect((explicitAttributes[.foregroundColor] as? UIColor) == UIColor.link)
    }

    @Test func `send and draft preserve explicit preview options`() throws {
        let options = LinkPreviewOptions(
            forceLargeMedia: true,
            forceSmallMedia: false,
            isDisabled: false,
            showAboveText: true,
            url: "https://example.com",
        )
        let text = FormattedText(entities: [], text: "https://example.com")

        guard case .inputMessageText(let input) = TelegramMessageSending.textContent(
            text,
            linkPreviewOptions: options,
        ) else {
            Issue.record("Expected text input content")
            return
        }
        #expect(input.linkPreviewOptions == options)

        let draft = try #require(TelegramDrafts.make(
            formattedText: text,
            replyMessageId: nil,
            linkPreviewOptions: options,
        ))
        guard case .draftMessageContentText(let content) = draft.content else {
            Issue.record("Expected text draft content")
            return
        }
        #expect(content.linkPreviewOptions == options)
    }

    @Test func `message description includes preview context without losing its text`() {
        let preview = makePreview(siteName: "Example", title: "Article title")
        let message = TDLibFixtures.message(
            id: 1,
            chatId: 2,
            date: 3,
            text: "https://example.com",
            linkPreview: preview,
        )

        #expect(telegramMessageContentDescription(message) ==
            "https://example.com, Link preview, Example, Article title")
    }

    @Test func `URL comparison ignores only an empty root slash`() throws {
        let withoutSlash = try #require(URL(string: "https://EXAMPLE.com"))
        let withSlash = try #require(URL(string: "https://example.com/"))
        let differentPath = try #require(URL(string: "https://example.com/article"))

        #expect(telegramURLsReferToSameResource(withoutSlash, withSlash))
        #expect(!telegramURLsReferToSameResource(withoutSlash, differentPath))
    }

    // MARK: Private

    private func makePreview(
        author: String = "",
        description: String = "",
        displayURL: String = "example.com",
        siteName: String = "Example",
        title: String = "Title",
        type: LinkPreviewType = .linkPreviewTypeArticle(.init(photo: nil)),
        url: String = "https://example.com",
    ) -> LinkPreview {
        LinkPreview(
            author: author,
            description: FormattedText(entities: [], text: description),
            displayUrl: displayURL,
            hasLargeMedia: false,
            instantViewVersion: 0,
            showAboveText: false,
            showLargeMedia: false,
            showMediaAboveDescription: false,
            siteName: siteName,
            skipConfirmation: true,
            title: title,
            type: type,
            url: url,
        )
    }
}
