// TelegramSharedMedia.swift

import Foundation
import Observation
import TDLibKit

// MARK: - TelegramSharedMediaCategory

enum TelegramSharedMediaCategory: String, CaseIterable, Identifiable, Sendable {
    case media
    case files
    case links
    case music
    case voice

    // MARK: Internal

    var id: Self { self }

    var title: String {
        switch self {
        case .media: "Media"
        case .files: "Files"
        case .links: "Links"
        case .music: "Music"
        case .voice: "Voice"
        }
    }

    var systemImage: String {
        switch self {
        case .media: "photo.on.rectangle"
        case .files: "doc"
        case .links: "link"
        case .music: "music.note"
        case .voice: "waveform"
        }
    }

    var filter: SearchMessagesFilter {
        switch self {
        case .media: .searchMessagesFilterPhotoAndVideo
        case .files: .searchMessagesFilterDocument
        case .links: .searchMessagesFilterUrl
        case .music: .searchMessagesFilterAudio
        case .voice: .searchMessagesFilterVoiceAndVideoNote
        }
    }
}

// MARK: - TelegramSharedMediaPage

struct TelegramSharedMediaPage: Equatable {
    var messages = [Message]()
    var nextFromMessageId: Int64 = 0
    var totalCount = -1
    var hasLoaded = false
    var isLoading = false
    var error: String?

    var hasMore: Bool { hasLoaded && nextFromMessageId != 0 }
}

// MARK: - TelegramSharedMediaStore

@MainActor @Observable final class TelegramSharedMediaStore {
    // MARK: Lifecycle

    init(chatId: Int64, service: any TelegramService) {
        self.chatId = chatId
        self.service = service
        self.pages = Dictionary(uniqueKeysWithValues: TelegramSharedMediaCategory.allCases.map {
            ($0, TelegramSharedMediaPage())
        })
    }

    // MARK: Internal

    let chatId: Int64

    private(set) var pages: [TelegramSharedMediaCategory: TelegramSharedMediaPage]

    func page(for category: TelegramSharedMediaCategory) -> TelegramSharedMediaPage {
        pages[category] ?? TelegramSharedMediaPage()
    }

    func load(_ category: TelegramSharedMediaCategory, reset: Bool = false) async {
        var page = reset ? TelegramSharedMediaPage() : page(for: category)
        guard !page.isLoading, reset || !page.hasLoaded || page.hasMore else { return }

        page.isLoading = true
        page.error = nil
        pages[category] = page

        do {
            let result = try await service.searchChatMessages(
                chatId: chatId,
                filter: category.filter,
                fromMessageId: reset ? 0 : page.nextFromMessageId,
                limit: 50,
                offset: 0,
                query: "",
                senderId: nil,
                topicId: nil,
            )
            var knownIds = Set(page.messages.map(\.id))
            page.messages.append(contentsOf: result.messages.filter { knownIds.insert($0.id).inserted })
            page.nextFromMessageId = result.nextFromMessageId
            page.totalCount = result.totalCount
            page.hasLoaded = true
            page.isLoading = false
            pages[category] = page
        } catch is CancellationError {
            page.isLoading = false
            pages[category] = page
        } catch {
            page.isLoading = false
            page.hasLoaded = true
            page.error = error.localizedDescription
            pages[category] = page
        }
    }

    // MARK: Private

    @ObservationIgnored private let service: any TelegramService
}

func telegramSharedMediaThumbnailFileId(_ message: Message) -> Int? {
    switch message.content {
    case .messagePhoto(let content):
        content.photo
            .sizes
            .min { lhs, rhs in
                abs(lhs.width - 320) < abs(rhs.width - 320)
            }?.photo
            .id
    case .messageVideo(let content):
        content.video.thumbnail?.file.id ?? content.cover?.sizes.first?.photo.id
    default:
        nil
    }
}

func telegramSharedMediaTitle(_ message: Message) -> String {
    switch message.content {
    case .messageDocument(let content):
        content.document.fileName.isEmpty ? "File" : content.document.fileName
    case .messageAudio(let content):
        telegramAudioTitle(content.audio)
    case .messageVoiceNote(let content):
        "Voice message, \(telegramClockDuration(content.voiceNote.duration))"
    case .messageVideoNote(let content):
        "Video message, \(telegramClockDuration(content.videoNote.duration))"
    case .messagePhoto:
        "Photo"
    case .messageVideo(let content):
        "Video, \(telegramClockDuration(content.video.duration))"
    default:
        telegramMessageContentDescription(message)
    }
}

func telegramSharedMediaSubtitle(_ message: Message) -> String {
    var parts = [String]()
    switch message.content {
    case .messageDocument(let content):
        let size = max(content.document.document.size, content.document.document.expectedSize)
        if size > 0 {
            parts.append(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
        }
        if !content.caption.text.isEmpty {
            parts.append(content.caption.text)
        }
    case .messageAudio(let content):
        if !content.audio.performer.isEmpty {
            parts.append(content.audio.performer)
        }
        parts.append(telegramClockDuration(content.audio.duration))
    case .messageVoiceNote(let content):
        if !content.caption.text.isEmpty {
            parts.append(content.caption.text)
        }
    case .messagePhoto(let content):
        if !content.caption.text.isEmpty {
            parts.append(content.caption.text)
        }
    case .messageVideo(let content):
        if !content.caption.text.isEmpty {
            parts.append(content.caption.text)
        }
    default:
        break
    }
    parts.append(telegramMessageDateDescription(message.date))
    return parts.joined(separator: ", ")
}
