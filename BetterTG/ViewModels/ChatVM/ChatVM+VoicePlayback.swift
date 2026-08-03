// ChatVM+VoicePlayback.swift

import Foundation
import TDLibKit

extension ChatVM {
    /// Plays a voice note, downloading it first if `knownLocalPath` isn't already resolved.
    /// Returns the local path once playback starts, so the caller can cache it - or `nil` if a
    /// download for this file is already in flight or the download failed.
    @MainActor func toggleVoiceMessage(_ messageVoiceNote: MessageVoiceNote, knownLocalPath: String?) async -> String? {
        let fileId = messageVoiceNote.voiceNote.voice.id
        voicePlaybackTrace(
            "activation fileId=\(fileId) hasPath=\(knownLocalPath != nil) "
                + "preparing=\(preparingVoiceNoteFileIds.contains(fileId))",
        )
        if let knownLocalPath {
            startVoicePlayback(path: knownLocalPath, duration: messageVoiceNote.voiceNote.duration)
            return knownLocalPath
        }
        guard !preparingVoiceNoteFileIds.contains(fileId) else { return nil }
        preparingVoiceNoteFileIds.insert(fileId)
        defer { preparingVoiceNoteFileIds.remove(fileId) }
        TelegramAudioPlayer.shared.stop()
        do {
            let file = try await service.downloadFile(
                fileId: fileId,
                limit: 0,
                offset: 0,
                priority: 32,
                synchronous: true,
            )
            guard file.local.isDownloadingCompleted, !file.local.path.isEmpty else { return nil }
            voicePlaybackTrace("download completed fileId=\(file.id) size=\(file.local.downloadedSize)")
            startVoicePlayback(path: file.local.path, duration: messageVoiceNote.voiceNote.duration)
            return file.local.path
        } catch {
            voicePlaybackTrace("download failed: \(error.localizedDescription)")
            log("Failed to download voice message:", error)
            return nil
        }
    }

    // MARK: Private

    @MainActor private func startVoicePlayback(path: String, duration: Int) {
        voicePlaybackTrace(
            "start requested exists=\(FileManager.default.fileExists(atPath: path)) duration=\(duration)",
        )
        TelegramAudioPlayer.shared.stop()
        Media.shared.toggle(with: path, duration: duration)
    }
}
