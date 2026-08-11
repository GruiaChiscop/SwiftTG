// TelegramOutgoingFileStaging.swift

import Foundation

// MARK: - TelegramFileName

enum TelegramFileName {
    static func sanitized(_ suggestedName: String, fallback: String = "Document") -> String {
        let trimmedName = suggestedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return fallback }

        let lastComponent = URL(fileURLWithPath: trimmedName).lastPathComponent
        guard !lastComponent.isEmpty,
              lastComponent != ".",
              lastComponent != "..",
              lastComponent != "/"
        else {
            return fallback
        }
        return lastComponent
    }
}

// MARK: - TelegramTemporaryFileCleanup

enum TelegramTemporaryFileCleanup {
    static func removeStaleItems(
        in directory: URL,
        olderThan staleAge: TimeInterval = 24 * 60 * 60,
        now: Date = Date(),
        fileManager: FileManager = .default,
    ) {
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles],
        ) else { return }

        var directories = [URL]()
        for case let itemURL as URL in enumerator {
            guard let values = try? itemURL.resourceValues(forKeys: [.contentModificationDateKey, .isDirectoryKey])
            else { continue }
            if values.isDirectory == true {
                directories.append(itemURL)
                continue
            }
            guard let modificationDate = values.contentModificationDate,
                  now.timeIntervalSince(modificationDate) >= staleAge
            else { continue }
            try? fileManager.removeItem(at: itemURL)
        }

        for directoryURL in directories.reversed() {
            guard (try? fileManager.contentsOfDirectory(atPath: directoryURL.path).isEmpty) == true else { continue }
            try? fileManager.removeItem(at: directoryURL)
        }
    }
}

// MARK: - TelegramOutgoingFileStaging

/// Keeps local upload sources alive until TDLib reports that their temporary messages were sent.
/// This is shared by voice notes and security-scoped documents, whose original provider URLs may
/// become unavailable immediately after their picker closes.
final class TelegramOutgoingFileStaging: @unchecked Sendable {
    // MARK: Lifecycle

    init(
        directory: URL,
        fileManager: FileManager = .default,
        staleFileAge: TimeInterval = 24 * 60 * 60,
        now: Date = Date(),
    ) {
        self.directory = directory
        self.fileManager = fileManager
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        TelegramTemporaryFileCleanup.removeStaleItems(
            in: directory,
            olderThan: staleFileAge,
            now: now,
            fileManager: fileManager,
        )
    }

    // MARK: Internal

    enum SuccessfulSendCleanup: Sendable {
        case removeImmediately
        case retainUntilStale
    }

    static let shared = TelegramOutgoingFileStaging(
        directory: FileManager.default.temporaryDirectory.appending(path: "BetterTGOutgoingFiles"),
    )

    func voiceNoteFileURL(identifier: UUID = UUID()) -> URL {
        let voiceDirectory = directory.appending(path: "VoiceNotes", directoryHint: .isDirectory)
        try? fileManager.createDirectory(at: voiceDirectory, withIntermediateDirectories: true)
        return voiceDirectory.appending(path: "voice_\(identifier.uuidString).ogg")
    }

    func videoNoteFileURL(identifier: UUID = UUID(), isRawRecording: Bool = false) -> URL {
        let videoDirectory = directory.appending(path: "VideoNotes", directoryHint: .isDirectory)
        try? fileManager.createDirectory(at: videoDirectory, withIntermediateDirectories: true)
        let prefix = isRawRecording ? "raw" : "video"
        let fileExtension = isRawRecording ? "mov" : "mp4"
        return videoDirectory.appending(path: "\(prefix)_\(identifier.uuidString).\(fileExtension)")
    }

    func videoNoteAssetWriterFileURL(identifier: UUID = UUID()) -> URL {
        let videoDirectory = directory.appending(path: "VideoNotes", directoryHint: .isDirectory)
        try? fileManager.createDirectory(at: videoDirectory, withIntermediateDirectories: true)
        return videoDirectory.appending(path: "raw_\(identifier.uuidString).mp4")
    }

    func videoNoteThumbnailFileURL(identifier: UUID = UUID()) -> URL {
        let videoDirectory = directory.appending(path: "VideoNotes", directoryHint: .isDirectory)
        try? fileManager.createDirectory(at: videoDirectory, withIntermediateDirectories: true)
        return videoDirectory.appending(path: "thumbnail_\(identifier.uuidString).jpeg")
    }

    /// Unlike documents, a picked photo has no source URL to stage from - the picker only hands
    /// over decoded image data, which has to be written somewhere before it can be referenced.
    /// Writing it under this same managed directory means it's covered by the stale-file sweep
    /// above and the same register/discard lifecycle as documents, instead of being left in the
    /// system temp directory with no cleanup of its own.
    func imageFileURL(identifier: UUID = UUID(), fileExtension: String = "jpeg") -> URL {
        let imagesDirectory = directory.appending(path: "Images", directoryHint: .isDirectory)
        try? fileManager.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        return imagesDirectory.appending(path: "\(identifier.uuidString).\(fileExtension)")
    }

    /// `@concurrent` (Swift 6.2) offloads this off the caller's context directly, without the
    /// manual `let destinationRoot = directory; let fileManager = fileManager` re-capture
    /// `Task.detached` needed to avoid pulling in `self` - and unlike `Task.detached`, cancelling
    /// the caller's own task now actually propagates into the file-coordination work below instead
    /// of only discarding its result afterward.
    @concurrent func stageDocument(
        sourceURL: URL,
        suggestedFileName: String,
        identifier: String = UUID().uuidString,
    ) async throws -> URL {
        let accessedSecurityScopedResource = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessedSecurityScopedResource {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var stagingResult: Result<URL, Error>?
        coordinator.coordinate(
            readingItemAt: sourceURL,
            options: [.withoutChanges],
            error: &coordinationError,
        ) { coordinatedURL in
            stagingResult = Result {
                let itemDirectory = directory
                    .appending(path: "Documents", directoryHint: .isDirectory)
                    .appending(path: identifier, directoryHint: .isDirectory)
                try fileManager.createDirectory(at: itemDirectory, withIntermediateDirectories: true)
                let destinationURL = itemDirectory.appending(
                    path: TelegramFileName.sanitized(suggestedFileName),
                )
                if fileManager.fileExists(atPath: destinationURL.path) {
                    try fileManager.removeItem(at: destinationURL)
                }
                try fileManager.copyItem(at: coordinatedURL, to: destinationURL)
                try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: destinationURL.path)
                return destinationURL
            }
        }

        if let coordinationError {
            throw coordinationError
        }
        guard let stagingResult else {
            throw TelegramFileTransferError.sourceUnavailable
        }
        return try stagingResult.get()
    }

    func register(fileURLs: [URL], chatId: Int64, temporaryMessageIds: [Int64]) {
        for (fileURL, messageId) in zip(fileURLs, temporaryMessageIds) {
            register(fileURL: fileURL, chatId: chatId, temporaryMessageId: messageId)
        }
    }

    func register(
        fileURL: URL,
        chatId: Int64,
        temporaryMessageId: Int64,
        successfulSendCleanup: SuccessfulSendCleanup = .removeImmediately,
    ) {
        register(
            fileURLs: [fileURL],
            chatId: chatId,
            temporaryMessageId: temporaryMessageId,
            successfulSendCleanup: successfulSendCleanup,
        )
    }

    func register(
        fileURLs: [URL],
        chatId: Int64,
        temporaryMessageId: Int64,
        successfulSendCleanup: SuccessfulSendCleanup = .removeImmediately,
    ) {
        guard !fileURLs.isEmpty else { return }
        let entry = Entry(fileURLs: fileURLs, successfulSendCleanup: successfulSendCleanup)
        let previousEntry = lock.withLock {
            stagedFiles.updateValue(entry, forKey: Key(chatId: chatId, messageId: temporaryMessageId))
        }
        if let previousEntry {
            for previousURL in previousEntry.fileURLs where !fileURLs.contains(previousURL) {
                removeStagedItem(at: previousURL)
            }
        }
    }

    func messageSendSucceeded(chatId: Int64, oldMessageId: Int64) {
        let entry = lock.withLock {
            stagedFiles.removeValue(forKey: Key(chatId: chatId, messageId: oldMessageId))
        }
        if let entry, entry.successfulSendCleanup == .removeImmediately {
            entry.fileURLs.forEach(removeStagedItem)
        }
    }

    func messageSendFailed(chatId: Int64, oldMessageId: Int64, failedMessageId: Int64) {
        lock.withLock {
            let oldKey = Key(chatId: chatId, messageId: oldMessageId)
            guard let entry = stagedFiles.removeValue(forKey: oldKey) else { return }
            stagedFiles[Key(chatId: chatId, messageId: failedMessageId)] = entry
        }
    }

    func messagesDeleted(chatId: Int64, messageIds: [Int64]) {
        let fileURLs = lock.withLock {
            messageIds.compactMap { messageId in
                stagedFiles.removeValue(forKey: Key(chatId: chatId, messageId: messageId))?.fileURLs
            }
            .flatMap(\.self)
        }
        for fileURL in fileURLs {
            removeStagedItem(at: fileURL)
        }
    }

    func discard(fileURL: URL) {
        lock.withLock {
            stagedFiles = stagedFiles.compactMapValues { entry in
                let remainingURLs = entry.fileURLs.filter { $0 != fileURL }
                guard !remainingURLs.isEmpty else { return nil }
                return Entry(
                    fileURLs: remainingURLs,
                    successfulSendCleanup: entry.successfulSendCleanup,
                )
            }
        }
        removeStagedItem(at: fileURL)
    }

    // MARK: Private

    private struct Key: Hashable {
        let chatId: Int64
        let messageId: Int64
    }

    private struct Entry {
        let fileURLs: [URL]
        let successfulSendCleanup: SuccessfulSendCleanup
    }

    private let directory: URL
    private let fileManager: FileManager
    private let lock = NSLock()
    private var stagedFiles = [Key: Entry]()

    private func removeStagedItem(at fileURL: URL) {
        try? fileManager.removeItem(at: fileURL)
        var parent = fileURL.deletingLastPathComponent()
        while parent.path.hasPrefix(directory.path), parent != directory {
            guard (try? fileManager.contentsOfDirectory(atPath: parent.path).isEmpty) == true else { break }
            try? fileManager.removeItem(at: parent)
            parent.deleteLastPathComponent()
        }
    }
}
