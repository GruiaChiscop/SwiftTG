// TelegramDocumentExport.swift

import Foundation
import UniformTypeIdentifiers

// MARK: - TelegramDocumentExport

enum TelegramDocumentExport {
    // MARK: Internal

    static func fileName(_ suggestedName: String) -> String {
        TelegramFileName.sanitized(suggestedName)
    }

    static func exportURL(
        sourceURL: URL,
        suggestedFileName: String,
        identifier: String,
    ) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
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
                    try stageCoordinatedFile(
                        sourceURL: coordinatedURL,
                        suggestedFileName: suggestedFileName,
                        identifier: identifier,
                    )
                }
            }

            if let coordinationError {
                throw coordinationError
            }
            guard let stagingResult else {
                throw TelegramFileTransferError.sourceUnavailable
            }
            return try stagingResult.get()
        }.value
    }

    static func previewURL(
        sourceURL: URL,
        suggestedFileName: String,
        mimeType: String,
        identifier: String,
    ) async throws -> URL {
        try await exportURL(
            sourceURL: sourceURL,
            suggestedFileName: previewFileName(suggestedFileName, mimeType: mimeType),
            identifier: "Preview-\(identifier)",
        )
    }

    static func previewFileName(_ suggestedName: String, mimeType: String) -> String {
        let sanitizedName = fileName(suggestedName)
        guard URL(filePath: sanitizedName).pathExtension.isEmpty,
              let normalizedMimeType = mimeType.split(separator: ";").first,
              let type = UTType(mimeType: String(normalizedMimeType)),
              let fileExtension = type.preferredFilenameExtension,
              !fileExtension.isEmpty
        else { return sanitizedName }
        return "\(sanitizedName).\(fileExtension)"
    }

    static func copyFile(from sourceURL: URL, to destinationURL: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            guard fileManager.fileExists(atPath: sourceURL.path) else {
                throw TelegramFileTransferError.sourceUnavailable
            }

            let temporaryURL = destinationURL
                .deletingLastPathComponent()
                .appendingPathComponent(".BetterTG-\(UUID().uuidString).tmp")
            try fileManager.copyItem(at: sourceURL, to: temporaryURL)
            do {
                if fileManager.fileExists(atPath: destinationURL.path) {
                    _ = try fileManager.replaceItemAt(destinationURL, withItemAt: temporaryURL)
                } else {
                    try fileManager.moveItem(at: temporaryURL, to: destinationURL)
                }
            } catch {
                try? fileManager.removeItem(at: temporaryURL)
                throw error
            }
        }.value
    }

    // MARK: Private

    private static func stageCoordinatedFile(
        sourceURL: URL,
        suggestedFileName: String,
        identifier: String,
    ) throws -> URL {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw TelegramFileTransferError.sourceUnavailable
        }

        let exportDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("BetterTGExports", isDirectory: true)
            .appendingPathComponent(identifier, isDirectory: true)
        TelegramTemporaryFileCleanup.removeStaleItems(
            in: exportDirectory.deletingLastPathComponent(),
            fileManager: fileManager,
        )
        try fileManager.createDirectory(at: exportDirectory, withIntermediateDirectories: true)

        let destinationURL = exportDirectory.appendingPathComponent(fileName(suggestedFileName))
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        do {
            try fileManager.linkItem(at: sourceURL, to: destinationURL)
        } catch {
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        }
        return destinationURL
    }
}

// MARK: - TelegramFileTransferError

enum TelegramFileTransferError: LocalizedError {
    case sourceUnavailable

    // MARK: Internal

    var errorDescription: String? {
        "The file is no longer available."
    }
}
