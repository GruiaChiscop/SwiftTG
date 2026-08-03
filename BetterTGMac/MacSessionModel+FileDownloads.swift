// MacSessionModel+FileDownloads.swift

import Foundation
import TDLibKit

extension MacSessionModel {
    func localPhotoPath(fileId: Int) async -> String? {
        await downloadedLocalPath(fileId: fileId, priority: 24)
    }

    func localDocumentPath(file: File, suggestedFileName: String) async -> String? {
        if let cachedPath = localFilePaths[file.id], FileManager.default.fileExists(atPath: cachedPath) {
            return cachedPath
        }
        if let existingURL = await MacDocumentDownloadStore.shared.existingURL(for: file) {
            localFilePaths[file.id] = existingURL.path
            return existingURL.path
        }
        guard let downloadedFile = try? await service.downloadFile(
            fileId: file.id,
            limit: 0,
            offset: 0,
            priority: 24,
            synchronous: true,
        ), downloadedFile.local.isDownloadingCompleted, !downloadedFile.local.path.isEmpty,
        let permanentURL = try? await MacDocumentDownloadStore.shared.storeDownloadedFile(
            downloadedFile,
            suggestedFileName: suggestedFileName,
        )
        else { return nil }
        localFilePaths[file.id] = permanentURL.path
        return permanentURL.path
    }

    func localDocumentCachePath(fileId: Int) async -> String? {
        await downloadedLocalPath(fileId: fileId, priority: 24)
    }

    func localVideoPath(fileId: Int) async -> String? {
        await downloadedLocalPath(fileId: fileId, priority: 32)
    }

    func localStickerPath(fileId: Int) async -> String? {
        await downloadedLocalPath(fileId: fileId, priority: 24)
    }

    func localVoiceNotePath(fileId: Int) async -> String? {
        await downloadedLocalPath(fileId: fileId, priority: 32)
    }

    // MARK: Private

    private func downloadedLocalPath(fileId: Int, priority: Int) async -> String? {
        if let cachedPath = localFilePaths[fileId] {
            return cachedPath
        }
        guard let file = try? await service.downloadFile(
            fileId: fileId,
            limit: 0,
            offset: 0,
            priority: priority,
            synchronous: true,
        ), file.local.isDownloadingCompleted, !file.local.path.isEmpty
        else { return nil }
        localFilePaths[fileId] = file.local.path
        return file.local.path
    }
}
