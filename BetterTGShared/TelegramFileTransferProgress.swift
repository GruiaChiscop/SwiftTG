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

    static func downloadLabel(file: File?) -> String {
        guard let percentage = percentage(file) else { return "Downloading" }
        return "Downloading \(percentage) percent"
    }

    static func downloadStatus(fileName: String, file: File?) -> String {
        "\(downloadLabel(file: file)), \(fileName)"
    }
}
