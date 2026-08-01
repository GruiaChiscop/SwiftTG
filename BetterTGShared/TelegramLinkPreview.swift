// TelegramLinkPreview.swift

import Foundation
import TDLibKit

// MARK: - TelegramLinkPreviewMedia

struct TelegramLinkPreviewMedia: Equatable {
    let fileId: Int
    let width: Int
    let height: Int
    let minithumbnailData: Data?

    var aspectRatio: Double? {
        guard width > 0, height > 0 else { return nil }
        return Double(width) / Double(height)
    }
}

// MARK: - TelegramLinkPreviewPresentation

struct TelegramLinkPreviewPresentation: Equatable {
    // MARK: Lifecycle

    init(_ preview: LinkPreview) {
        self.url = Self.normalizedURL(preview.url)
        self.displayURL = Self.firstNonempty(preview.displayUrl, preview.url)
        self.siteName = Self.firstNonempty(
            preview.siteName,
            url?.host(percentEncoded: false) ?? "",
            displayURL,
            "Link",
        )
        self.title = preview.title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.author = preview.author.trimmingCharacters(in: .whitespacesAndNewlines)
        self.summary = preview.description.text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.media = Self.media(from: preview.type)
        self.hasLargeMedia = preview.hasLargeMedia
        self.showAboveText = preview.showAboveText
        self.showLargeMedia = preview.showLargeMedia
        self.showMediaAboveDescription = preview.showMediaAboveDescription
    }

    // MARK: Internal

    let url: URL?
    let displayURL: String
    let siteName: String
    let title: String
    let author: String
    let summary: String
    let media: TelegramLinkPreviewMedia?
    let hasLargeMedia: Bool
    let showAboveText: Bool
    let showLargeMedia: Bool
    let showMediaAboveDescription: Bool

    var accessibilityDescription: String {
        var parts = ["Link preview"]
        for value in [siteName, title, author, summary] where !value.isEmpty && !parts.contains(value) {
            parts.append(value)
        }
        return parts.joined(separator: ", ")
    }

    var accessibilityLinkLabel: String {
        "Link preview: \(Self.firstNonempty(title, siteName, displayURL))"
    }

    // MARK: Private

    private static func media(from type: LinkPreviewType) -> TelegramLinkPreviewMedia? {
        switch type {
        case .linkPreviewTypeAlbum(let content):
            guard let first = content.media.first else { return nil }
            switch first {
            case .linkPreviewAlbumMediaPhoto(let photo):
                return media(from: photo.photo)
            case .linkPreviewAlbumMediaVideo(let video):
                return media(from: video.video)
            }
        case .linkPreviewTypeAnimation(let content):
            return media(from: content.animation)
        case .linkPreviewTypeApp(let content):
            return media(from: content.photo)
        case .linkPreviewTypeArticle(let content):
            return content.photo.flatMap(media(from:))
        case .linkPreviewTypeAudio(let content):
            return media(from: content.audio)
        case .linkPreviewTypeBackground(let content):
            return content.document.flatMap(media(from:))
        case .linkPreviewTypeChannelBoost(let content):
            return content.photo.flatMap(media(from:))
        case .linkPreviewTypeChat(let content):
            return content.photo.flatMap(media(from:))
        case .linkPreviewTypeDirectMessagesChat(let content):
            return content.photo.flatMap(media(from:))
        case .linkPreviewTypeDocument(let content):
            return media(from: content.document)
        case .linkPreviewTypeEmbeddedAnimationPlayer(let content):
            return content.animation.flatMap(media(from:)) ?? content.thumbnail.flatMap(media(from:))
        case .linkPreviewTypeEmbeddedAudioPlayer(let content):
            return content.audio.flatMap(media(from:)) ?? content.thumbnail.flatMap(media(from:))
        case .linkPreviewTypeEmbeddedVideoPlayer(let content):
            return content.thumbnail.flatMap(media(from:)) ?? content.video.flatMap(media(from:))
        case .linkPreviewTypeGiftCollection(let content):
            return content.icons.first.flatMap(media(from:))
        case .linkPreviewTypePhoto(let content):
            return media(from: content.photo)
        case .linkPreviewTypeSticker(let content):
            return media(from: content.sticker)
        case .linkPreviewTypeStickerSet(let content):
            return content.stickers.first.flatMap(media(from:))
        case .linkPreviewTypeStoryAlbum(let content):
            return content.photoIcon.flatMap(media(from:)) ?? content.videoIcon.flatMap(media(from:))
        case .linkPreviewTypeSupergroupBoost(let content):
            return content.photo.flatMap(media(from:))
        case .linkPreviewTypeTheme(let content):
            return content.documents.first.flatMap(media(from:))
        case .linkPreviewTypeUser(let content):
            return content.photo.flatMap(media(from:))
        case .linkPreviewTypeVideo(let content):
            return content.cover.flatMap(media(from:)) ?? media(from: content.video)
        case .linkPreviewTypeVideoChat(let content):
            return content.photo.flatMap(media(from:))
        case .linkPreviewTypeVideoNote(let content):
            guard let thumbnail = content.videoNote.thumbnail else { return nil }
            return media(from: thumbnail, minithumbnail: content.videoNote.minithumbnail)
        case .linkPreviewTypeWebApp(let content):
            return content.photo.flatMap(media(from:))
        default:
            return nil
        }
    }

    private static func media(from photo: Photo) -> TelegramLinkPreviewMedia? {
        guard let size = preferredPhotoSize(from: photo.sizes) else { return nil }
        return TelegramLinkPreviewMedia(
            fileId: size.photo.id,
            width: size.width,
            height: size.height,
            minithumbnailData: photo.minithumbnail?.data,
        )
    }

    private static func media(from photo: ChatPhoto) -> TelegramLinkPreviewMedia? {
        guard let size = preferredPhotoSize(from: photo.sizes) else { return nil }
        return TelegramLinkPreviewMedia(
            fileId: size.photo.id,
            width: size.width,
            height: size.height,
            minithumbnailData: photo.minithumbnail?.data,
        )
    }

    private static func media(from animation: Animation) -> TelegramLinkPreviewMedia? {
        guard let thumbnail = animation.thumbnail else { return nil }
        return media(from: thumbnail, minithumbnail: animation.minithumbnail)
    }

    private static func media(from audio: Audio) -> TelegramLinkPreviewMedia? {
        guard let thumbnail = audio.albumCoverThumbnail ?? audio.externalAlbumCovers.first else { return nil }
        return media(from: thumbnail, minithumbnail: audio.albumCoverMinithumbnail)
    }

    private static func media(from document: Document) -> TelegramLinkPreviewMedia? {
        guard let thumbnail = document.thumbnail else { return nil }
        return media(from: thumbnail, minithumbnail: document.minithumbnail)
    }

    private static func media(from sticker: Sticker) -> TelegramLinkPreviewMedia? {
        guard let thumbnail = sticker.thumbnail else { return nil }
        return media(from: thumbnail, minithumbnail: nil)
    }

    private static func media(from video: Video) -> TelegramLinkPreviewMedia? {
        guard let thumbnail = video.thumbnail else { return nil }
        return media(from: thumbnail, minithumbnail: video.minithumbnail)
    }

    private static func media(
        from thumbnail: Thumbnail,
        minithumbnail: Minithumbnail?,
    ) -> TelegramLinkPreviewMedia {
        TelegramLinkPreviewMedia(
            fileId: thumbnail.file.id,
            width: thumbnail.width,
            height: thumbnail.height,
            minithumbnailData: minithumbnail?.data,
        )
    }

    private static func preferredPhotoSize(from sizes: [PhotoSize]) -> PhotoSize? {
        let sorted = sizes.sorted { lhs, rhs in
            max(lhs.width, lhs.height) < max(rhs.width, rhs.height)
        }
        return sorted.first { max($0.width, $0.height) >= 800 } ?? sorted.last
    }

    private static func normalizedURL(_ value: String) -> URL? {
        guard !value.isEmpty else { return nil }
        if let components = URLComponents(string: value), components.scheme != nil {
            return components.url
        }
        return URL(string: "https://\(value)")
    }

    private static func firstNonempty(_ values: String...) -> String {
        values.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

func telegramMessageLinkPreview(_ message: Message) -> LinkPreview? {
    guard case .messageText(let content) = message.content else { return nil }
    return content.linkPreview
}

func telegramMessageLinkPreviewOptions(_ message: Message) -> LinkPreviewOptions? {
    guard case .messageText(let content) = message.content else { return nil }
    return content.linkPreviewOptions
}

func telegramURLsReferToSameResource(_ lhs: URL, _ rhs: URL) -> Bool {
    func normalizedComponents(for url: URL) -> URLComponents? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        if components.path == "/" {
            components.path = ""
        }
        return components
    }

    return normalizedComponents(for: lhs) == normalizedComponents(for: rhs)
}
