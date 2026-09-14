// TelegramAutoDownloadPolicyTests.swift

@testable import BetterTG
import Testing
import TDLibKit

struct TelegramAutoDownloadPolicyTests {
    // MARK: Internal

    @Test func `disabled settings block every kind regardless of size`() {
        let settings = Self.settings(enabled: false, photo: 10_000_000, video: 10_000_000, other: 10_000_000)
        #expect(!TelegramAutoDownloadPolicy.shouldAutoDownload(kind: .photo, fileSize: 1, settings: settings))
        #expect(!TelegramAutoDownloadPolicy.shouldAutoDownload(kind: .video, fileSize: 1, settings: settings))
        #expect(!TelegramAutoDownloadPolicy.shouldAutoDownload(kind: .document, fileSize: 1, settings: settings))
        #expect(!TelegramAutoDownloadPolicy.shouldAutoDownload(kind: .voiceNote, fileSize: 1, settings: settings))
    }

    @Test func `each kind is checked against its own cap`() {
        let settings = Self.settings(enabled: true, photo: 1_000_000, video: 2_000_000, other: 3_000_000)
        #expect(TelegramAutoDownloadPolicy.shouldAutoDownload(kind: .photo, fileSize: 1_000_000, settings: settings))
        #expect(!TelegramAutoDownloadPolicy.shouldAutoDownload(kind: .photo, fileSize: 1_000_001, settings: settings))
        #expect(TelegramAutoDownloadPolicy.shouldAutoDownload(kind: .video, fileSize: 2_000_000, settings: settings))
        #expect(!TelegramAutoDownloadPolicy.shouldAutoDownload(kind: .video, fileSize: 2_000_001, settings: settings))
        #expect(TelegramAutoDownloadPolicy.shouldAutoDownload(kind: .document, fileSize: 3_000_000, settings: settings))
        #expect(!TelegramAutoDownloadPolicy.shouldAutoDownload(kind: .document, fileSize: 3_000_001, settings: settings))
    }

    @Test func `voice notes stay auto-downloadable up to the 2MB floor even under a tighter other cap`() {
        let settings = Self.settings(enabled: true, photo: 0, video: 0, other: 100_000)
        #expect(TelegramAutoDownloadPolicy.shouldAutoDownload(
            kind: .voiceNote,
            fileSize: TelegramAutoDownloadPolicy.minimumVoiceNoteAllowance,
            settings: settings,
        ))
        #expect(!TelegramAutoDownloadPolicy.shouldAutoDownload(
            kind: .voiceNote,
            fileSize: TelegramAutoDownloadPolicy.minimumVoiceNoteAllowance + 1,
            settings: settings,
        ))
    }

    @Test func `voice notes still use the larger other cap when it exceeds the floor`() {
        let settings = Self.settings(enabled: true, photo: 0, video: 0, other: 5_000_000)
        #expect(TelegramAutoDownloadPolicy.shouldAutoDownload(kind: .voiceNote, fileSize: 5_000_000, settings: settings))
        #expect(!TelegramAutoDownloadPolicy.shouldAutoDownload(kind: .voiceNote, fileSize: 5_000_001, settings: settings))
    }

    @Test func `unknown size (zero) is allowed through rather than blocked`() {
        let settings = Self.settings(enabled: true, photo: 1, video: 1, other: 1)
        #expect(TelegramAutoDownloadPolicy.shouldAutoDownload(kind: .document, fileSize: 0, settings: settings))
    }

    // MARK: Private

    private static func settings(enabled: Bool, photo: Int, video: Int64, other: Int64) -> AutoDownloadSettings {
        AutoDownloadSettings(
            isAutoDownloadEnabled: enabled,
            maxOtherFileSize: other,
            maxPhotoFileSize: photo,
            maxVideoFileSize: video,
            preloadLargeVideos: false,
            preloadNextAudio: false,
            preloadStories: false,
            useLessDataForCalls: false,
            videoUploadBitrate: 0,
        )
    }
}
