// ChatVM+VoicePlayback.swift

import Foundation
import TDLibKit

extension ChatVM {
    /// Plays a voice note, downloading it first if `knownLocalPath` isn't already resolved.
    /// Returns the local path once playback starts, so the caller can cache it - or `nil` if a
    /// download for this file is already in flight or the download failed.
    @MainActor func toggleVoiceMessage(
        message: Message,
        content: MessageVoiceNote,
        knownLocalPath: String?,
    ) async -> String? {
        let presentation = TelegramVoiceNotePresentation(message: message, content: content)
        let messageVoiceNote = content
        let fileId = messageVoiceNote.voiceNote.voice.id
        voicePlaybackTrace(
            "activation fileId=\(fileId) hasPath=\(knownLocalPath != nil) "
                + "preparing=\(preparingVoiceNoteFileIds.contains(fileId))",
        )
        if let knownLocalPath {
            guard await prepareViewOnceVoicePlayback(
                message: message,
                path: knownLocalPath,
                presentation: presentation,
            ) else { return nil }
            startVoicePlayback(
                path: knownLocalPath,
                duration: messageVoiceNote.voiceNote.duration,
                allowsSeeking: presentation.allowsSeeking,
            )
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
            guard await prepareViewOnceVoicePlayback(
                message: message,
                path: file.local.path,
                presentation: presentation,
            ) else { return nil }
            startVoicePlayback(
                path: file.local.path,
                duration: messageVoiceNote.voiceNote.duration,
                allowsSeeking: presentation.allowsSeeking,
            )
            return file.local.path
        } catch {
            voicePlaybackTrace("download failed: \(error.localizedDescription)")
            log("Failed to download voice message:", error)
            return nil
        }
    }

    // MARK: Private

    @MainActor private func prepareViewOnceVoicePlayback(
        message: Message,
        path: String,
        presentation: TelegramVoiceNotePresentation,
    ) async -> Bool {
        guard presentation.shouldOpenMessageContent else { return true }
        if openedViewOnceVoiceNoteMessageIds.contains(message.id) {
            return Media.shared.savedMediaPath == path
        }
        guard openingViewOnceVoiceNoteMessageIds.insert(message.id).inserted else { return false }
        defer { openingViewOnceVoiceNoteMessageIds.remove(message.id) }
        do {
            _ = try await service.openMessageContent(chatId: message.chatId, messageId: message.id)
            guard !Task.isCancelled else { return false }
            openedViewOnceVoiceNoteMessageIds.insert(message.id)
            return true
        } catch {
            guard !Task.isCancelled else { return false }
            messageActionError = "Voice message couldn't be opened: \(telegramErrorDescription(error))"
            return false
        }
    }

    @MainActor private func startVoicePlayback(path: String, duration: Int, allowsSeeking: Bool) {
        voicePlaybackTrace(
            "start requested exists=\(FileManager.default.fileExists(atPath: path)) duration=\(duration)",
        )
        TelegramAudioPlayer.shared.stop()
        Media.shared.toggle(with: path, duration: duration, allowsSeeking: allowsSeeking)
    }
}
