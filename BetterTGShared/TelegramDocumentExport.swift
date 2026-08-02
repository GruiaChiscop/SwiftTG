// TelegramDocumentExport.swift

import Foundation

// MARK: - TelegramDocumentExport

enum TelegramDocumentExport {
    // MARK: Internal

    static func fileName(_ suggestedName: String) -> String {
        let trimmedName = suggestedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return "Document" }

        let lastComponent = URL(fileURLWithPath: trimmedName).lastPathComponent
        guard !lastComponent.isEmpty, lastComponent != ".", lastComponent != ".." else {
            return "Document"
        }
        return lastComponent
    }

    static func stagedURL(
        sourceURL: URL,
        suggestedFileName: String,
        identifier: String,
        forceCopy: Bool = false,
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
                        forceCopy: forceCopy,
                    )
                }
            }

            if let coordinationError {
                throw coordinationError
            }
            guard let stagingResult else {
                throw TelegramDocumentExportError.sourceUnavailable
            }
            return try stagingResult.get()
        }.value
    }

    static func copyFile(from sourceURL: URL, to destinationURL: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            guard fileManager.fileExists(atPath: sourceURL.path) else {
                throw TelegramDocumentExportError.sourceUnavailable
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
        forceCopy: Bool,
    ) throws -> URL {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw TelegramDocumentExportError.sourceUnavailable
        }

        let exportDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("BetterTGExports", isDirectory: true)
            .appendingPathComponent(identifier, isDirectory: true)
        try fileManager.createDirectory(at: exportDirectory, withIntermediateDirectories: true)

        let destinationURL = exportDirectory.appendingPathComponent(fileName(suggestedFileName))
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        if forceCopy {
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        } else {
            do {
                try fileManager.linkItem(at: sourceURL, to: destinationURL)
            } catch {
                try fileManager.copyItem(at: sourceURL, to: destinationURL)
            }
        }
        return destinationURL
    }
}

// MARK: - TelegramDocumentExportError

enum TelegramDocumentExportError: LocalizedError {
    case sourceUnavailable

    // MARK: Internal

    var errorDescription: String? {
        "The downloaded file is no longer available."
    }
}
