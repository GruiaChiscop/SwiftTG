// TelegramFileTransferProgress.swift

import Foundation
import TDLibKit

enum TelegramFileTransferProgress {
    static func fraction(_ file: File?) -> Double? {
        guard let file else { return nil }
        let totalBytes = max(file.size, file.expectedSize)
        guard totalBytes > 0 else { return nil }
        return min(max(Double(file.local.downloadedSize) / Double(totalBytes), 0), 1)
    }

    static func percentage(_ file: File?) -> Int? {
        fraction(file).map { Int(($0 * 100).rounded()) }
    }

    /// The file's total size, formatted, or `nil` if TDLib hasn't reported one yet.
    static func totalSizeLabel(_ file: File?) -> String? {
        guard let file else { return nil }
        return totalSizeLabel(bytes: max(file.size, file.expectedSize))
    }

    /// Prefer this over `totalSizeLabel(_ file:)` when a message's own content already carries a
    /// `File` (e.g. `Document.document`) - that one is populated synchronously with the message
    /// and has a real size even for a file that's never been touched, unlike the live,
    /// download-tracking `File?` `AsyncTdFile` hands to its placeholder, which stays `nil` until
    /// an actual transfer starts and so has no size to report while a file just sits unopened.
    static func totalSizeLabel(bytes: Int64) -> String? {
        guard bytes > 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// `nil` when the file isn't actually being transferred right now - auto-download gated it
    /// off, or nothing has been tapped yet. Callers should omit the status text entirely in that
    /// case rather than claim a download is happening when it isn't.
    static func downloadLabel(file: File?) -> String? {
        guard file?.local.isDownloadingActive == true else { return nil }
        guard let percentage = percentage(file), let totalSizeLabel = totalSizeLabel(file) else {
            return "Downloading"
        }
        let downloadedSizeLabel = ByteCountFormatter.string(
            fromByteCount: Int64(file?.local.downloadedSize ?? 0),
            countStyle: .file,
        )
        return "Downloading \(downloadedSizeLabel) of \(totalSizeLabel), \(percentage) percent"
    }

    /// The size shown/announced for a file that isn't currently downloading, if TDLib has
    /// reported one - `nil` while an actual transfer is active, since `downloadLabel` already
    /// covers that case with the running progress instead.
    static func idleSizeLabel(file: File?) -> String? {
        guard file?.local.isDownloadingActive != true else { return nil }
        return totalSizeLabel(file)
    }

    static func downloadStatus(fileName: String, file: File?, fallbackSizeLabel: String? = nil) -> String {
        if let label = downloadLabel(file: file) {
            return "\(label), \(fileName)"
        }
        if let size = idleSizeLabel(file: file) ?? fallbackSizeLabel {
            return "\(fileName), \(size)"
        }
        return fileName
    }
}
