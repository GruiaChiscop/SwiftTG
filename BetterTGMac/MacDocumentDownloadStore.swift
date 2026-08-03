// MacDocumentDownloadStore.swift

import Foundation
import TDLibKit

actor MacDocumentDownloadStore {
    // MARK: Lifecycle

    private init() {
        self.pathsByIdentifier = UserDefaults.standard
            .dictionary(forKey: Self.pathsDefaultsKey) as? [String: String] ?? [:]
    }

    // MARK: Internal

    static let shared = MacDocumentDownloadStore()

    func existingURL(for file: File) -> URL? {
        let identifier = persistentIdentifier(for: file)
        guard let path = pathsByIdentifier[identifier] else { return nil }
        guard fileManager.fileExists(atPath: path) else {
            pathsByIdentifier.removeValue(forKey: identifier)
            persistPaths()
            return nil
        }
        return URL(filePath: path)
    }

    func storeDownloadedFile(_ file: File, suggestedFileName: String) async throws -> URL {
        if let existingURL = existingURL(for: file) {
            return existingURL
        }
        guard file.local.isDownloadingCompleted, !file.local.path.isEmpty else {
            throw TelegramFileTransferError.sourceUnavailable
        }

        let identifier = persistentIdentifier(for: file)
        if let existingTask = inFlightMaterializations[identifier] {
            return try await existingTask.value
        }
        let sourceURL = URL(filePath: file.local.path)
        let destinationURL = uniqueDestinationURL(suggestedFileName: suggestedFileName)
        reservedPaths.insert(destinationURL.path)
        let materialization = Task<URL, any Swift.Error> {
            try await Self.materializeFile(from: sourceURL, to: destinationURL)
            return destinationURL
        }
        inFlightMaterializations[identifier] = materialization
        do {
            let storedURL = try await materialization.value
            reservedPaths.remove(destinationURL.path)
            inFlightMaterializations.removeValue(forKey: identifier)
            pathsByIdentifier[identifier] = storedURL.path
            persistPaths()
            return storedURL
        } catch {
            reservedPaths.remove(destinationURL.path)
            inFlightMaterializations.removeValue(forKey: identifier)
            throw error
        }
    }

    // MARK: Private

    private static let pathsDefaultsKey = "BetterTGMac.documentDownloadPaths"

    private let fileManager = FileManager.default
    private var inFlightMaterializations = [String: Task<URL, any Swift.Error>]()
    private var pathsByIdentifier: [String: String]
    private var reservedPaths = Set<String>()

    private nonisolated static func materializeFile(from sourceURL: URL, to destinationURL: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            guard fileManager.fileExists(atPath: sourceURL.path) else {
                throw TelegramFileTransferError.sourceUnavailable
            }

            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        }.value
    }

    private func persistentIdentifier(for file: File) -> String {
        file.remote.uniqueId.isEmpty ? "file-\(file.id)" : file.remote.uniqueId
    }

    private func uniqueDestinationURL(suggestedFileName: String) -> URL {
        let downloadsDirectory = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true)
        let fileName = TelegramDocumentExport.fileName(suggestedFileName)
        let originalURL = downloadsDirectory.appendingPathComponent(fileName)
        guard destinationIsAvailable(originalURL) else {
            let fileExtension = originalURL.pathExtension
            let baseName = originalURL.deletingPathExtension().lastPathComponent
            var suffix = 2
            while true {
                let candidateName = fileExtension.isEmpty
                    ? "\(baseName) \(suffix)"
                    : "\(baseName) \(suffix).\(fileExtension)"
                let candidateURL = downloadsDirectory.appendingPathComponent(candidateName)
                if destinationIsAvailable(candidateURL) {
                    return candidateURL
                }
                suffix += 1
            }
        }
        return originalURL
    }

    private func destinationIsAvailable(_ url: URL) -> Bool {
        !fileManager.fileExists(atPath: url.path) && !reservedPaths.contains(url.path)
    }

    private func persistPaths() {
        UserDefaults.standard.set(pathsByIdentifier, forKey: Self.pathsDefaultsKey)
    }
}
