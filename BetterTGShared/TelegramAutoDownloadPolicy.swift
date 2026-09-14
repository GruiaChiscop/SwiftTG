// TelegramAutoDownloadPolicy.swift

@preconcurrency import TDLibKit

// MARK: - TelegramAutoDownloadKind

/// The categories `AutoDownloadSettings` actually distinguishes. Thumbnails, avatars, stickers,
/// and link-preview images are deliberately not represented here - like Telegram-iOS, those stay
/// exempt from auto-download gating everywhere they're used.
enum TelegramAutoDownloadKind {
    case photo
    case video
    case document
    /// Voice messages stay listenable even under a tight "other" cap, mirroring Telegram-iOS's
    /// `max(2 MB, category.sizeLimit)` exception (there, this also bypasses the per-peer-kind
    /// toggle, which our simpler TDLib-native settings model doesn't have to begin with).
    case voiceNote
}

// MARK: - TelegramAutoDownloadPolicy

enum TelegramAutoDownloadPolicy {
    // MARK: Internal

    static let minimumVoiceNoteAllowance: Int64 = 2_097_152

    /// `fileSize` should be the caller's best known size for the file - typically
    /// `max(file.size, file.expectedSize)` from the `File` already embedded in the message
    /// content, so this never needs a network round trip to decide.
    static func shouldAutoDownload(
        kind: TelegramAutoDownloadKind,
        fileSize: Int64,
        settings: AutoDownloadSettings,
    ) -> Bool {
        guard settings.isAutoDownloadEnabled else { return false }
        guard fileSize > 0 else { return true }
        return fileSize <= limit(for: kind, settings: settings)
    }

    // MARK: Private

    private static func limit(for kind: TelegramAutoDownloadKind, settings: AutoDownloadSettings) -> Int64 {
        switch kind {
        case .photo: Int64(settings.maxPhotoFileSize)
        case .video: settings.maxVideoFileSize
        case .document: settings.maxOtherFileSize
        case .voiceNote: max(minimumVoiceNoteAllowance, settings.maxOtherFileSize)
        }
    }
}
