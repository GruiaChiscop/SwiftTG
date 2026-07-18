// TelegramVoiceNoteStaging.swift

import Foundation

final class TelegramVoiceNoteStaging: @unchecked Sendable {
    // MARK: Lifecycle

    init(
        directory: URL,
        fileManager: FileManager = .default,
        staleFileAge: TimeInterval = 24 * 60 * 60,
        now: Date = Date(),
    ) {
        self.directory = directory
        self.fileManager = fileManager
        self.staleFileAge = staleFileAge
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        removeStaleFiles(now: now)
    }

    // MARK: Internal

    static let shared = TelegramVoiceNoteStaging(
        directory: FileManager.default.temporaryDirectory.appending(path: "BetterTGVoiceNotes"),
    )

    func fileURL(identifier: UUID = UUID()) -> URL {
        directory.appending(path: "voice_\(identifier.uuidString).ogg")
    }

    func register(fileURL: URL, chatId: Int64, temporaryMessageId: Int64) {
        let previousURL = lock.withLock {
            stagedFiles.updateValue(fileURL, forKey: Key(chatId: chatId, messageId: temporaryMessageId))
        }
        if let previousURL, previousURL != fileURL {
            try? fileManager.removeItem(at: previousURL)
        }
    }

    func messageSendSucceeded(chatId: Int64, oldMessageId: Int64) {
        let fileURL = lock.withLock {
            stagedFiles.removeValue(forKey: Key(chatId: chatId, messageId: oldMessageId))
        }
        if let fileURL {
            try? fileManager.removeItem(at: fileURL)
        }
    }

    func messageSendFailed(chatId: Int64, oldMessageId: Int64, failedMessageId: Int64) {
        lock.withLock {
            let oldKey = Key(chatId: chatId, messageId: oldMessageId)
            guard let fileURL = stagedFiles.removeValue(forKey: oldKey) else { return }
            stagedFiles[Key(chatId: chatId, messageId: failedMessageId)] = fileURL
        }
    }

    func messagesDeleted(chatId: Int64, messageIds: [Int64]) {
        let fileURLs = lock.withLock {
            messageIds.compactMap { messageId in
                stagedFiles.removeValue(forKey: Key(chatId: chatId, messageId: messageId))
            }
        }
        for fileURL in fileURLs {
            try? fileManager.removeItem(at: fileURL)
        }
    }

    func discard(fileURL: URL) {
        lock.withLock {
            stagedFiles = stagedFiles.filter { $0.value != fileURL }
        }
        try? fileManager.removeItem(at: fileURL)
    }

    // MARK: Private

    private struct Key: Hashable {
        let chatId: Int64
        let messageId: Int64
    }

    private let directory: URL
    private let fileManager: FileManager
    private let staleFileAge: TimeInterval
    private let lock = NSLock()
    private var stagedFiles = [Key: URL]()

    private func removeStaleFiles(now: Date) {
        guard let files = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles,
        ) else { return }
        for fileURL in files {
            guard fileURL.pathExtension.lowercased() == "ogg",
                  let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]),
                  let modificationDate = values.contentModificationDate,
                  now.timeIntervalSince(modificationDate) >= staleFileAge
            else { continue }
            try? fileManager.removeItem(at: fileURL)
        }
    }
}
