// ChatVM+Composer.swift

import Combine
import SwiftUI
@preconcurrency import TDLibKit

extension ChatVM {
    // MARK: Composer/Recorder facade

    var text: AttributedString {
        get { composer.text }
        set { composer.text = newValue }
    }

    var editMessageText: AttributedString {
        get { composer.editMessageText }
        set { composer.editMessageText = newValue }
    }

    var editCustomMessage: CustomMessage? {
        get { composer.editCustomMessage }
        set { composer.editCustomMessage = newValue }
    }

    var replyMessage: CustomMessage? {
        get { composer.replyMessage }
        set { composer.replyMessage = newValue }
    }

    var showSendButton: Bool {
        get { composer.showSendButton }
        set { composer.showSendButton = newValue }
    }

    var showDetail: Bool {
        get { composer.showDetail }
        set { composer.showDetail = newValue }
    }

    var displayedImages: [SelectedImage] {
        get { composer.displayedImages }
        set {
            let retainedURLs = Set(newValue.map(\.url))
            for removedImage in composer.displayedImages where !retainedURLs.contains(removedImage.url) {
                TelegramOutgoingFileStaging.shared.discard(fileURL: removedImage.url)
            }
            composer.displayedImages = newValue
        }
    }

    var displayedDocuments: [URL] {
        get { composer.displayedDocuments }
        set {
            let retainedURLs = Set(newValue)
            for removedURL in composer.displayedDocuments where !retainedURLs.contains(removedURL) {
                TelegramOutgoingFileStaging.shared.discard(fileURL: removedURL)
            }
            composer.displayedDocuments = newValue
        }
    }

    var showCameraView: Bool {
        get { composer.showCameraView }
        set { composer.showCameraView = newValue }
    }

    var showDocumentPicker: Bool {
        get { composer.showDocumentPicker }
        set { composer.showDocumentPicker = newValue }
    }

    var showPhotoPickerView: Bool {
        get { composer.showPhotoPickerView }
        set { composer.showPhotoPickerView = newValue }
    }

    var activeLinkPreviewComposer: TelegramLinkPreviewComposer {
        composer.activeLinkPreviewComposer
    }

    var sendMessageTask: Task<Void, Never>? {
        get { composer.sendMessageTask }
        set { composer.sendMessageTask = newValue }
    }

    var isSubmittingMessage: Bool {
        get { composer.isSubmittingMessage }
        set { composer.isSubmittingMessage = newValue }
    }

    var errorShown: Bool {
        get { voiceRecorder.errorShown }
        set { voiceRecorder.errorShown = newValue }
    }

    var recordingVoiceNote: Bool {
        get { voiceRecorder.recordingVoiceNote }
        set { voiceRecorder.recordingVoiceNote = newValue }
    }

    var voiceNoteIsViewOnce: Bool {
        get { voiceRecorder.isViewOnce }
        set { voiceRecorder.isViewOnce = newValue }
    }

    var recordingLocked: Bool {
        get { voiceRecorder.recordingLocked }
        set { voiceRecorder.recordingLocked = newValue }
    }

    var recordingDragTranslation: CGSize {
        get { voiceRecorder.recordingDragTranslation }
        set { voiceRecorder.recordingDragTranslation = newValue }
    }

    var timerCount: Double {
        get { voiceRecorder.timerCount }
        set { voiceRecorder.timerCount = newValue }
    }

    var formattedTimerCount: String { voiceRecorder.formattedTimerCount }

    var wave: [Float] {
        get { voiceRecorder.wave }
        set { voiceRecorder.wave = newValue }
    }

    var recordingVideoNote: Bool { videoRecorder.isRecording }
    var pausedVideoNote: Bool { videoRecorder.isPaused }
    var preparingVideoNote: Bool { videoRecorder.isPreparing }
    var finalizingVideoNote: Bool { videoRecorder.isFinalizing }
    var videoRecordingDuration: TimeInterval { videoRecorder.duration }

    // MARK: Sending/recording

    func sendMessage(schedulingState: MessageSchedulingState? = nil) async {
        guard !composer.isSubmittingMessage else { return }
        let isEditing = composer.editCustomMessage != nil
        composer.isSubmittingMessage = true
        messageActionError = nil
        defer { composer.isSubmittingMessage = false }

        do {
            try await composer.sendMessage(schedulingState: schedulingState)
        } catch {
            guard !Task.isCancelled else { return }
            let action = isEditing ? "updated" : "sent"
            messageActionError = "Message couldn't be \(action): \(telegramErrorDescription(error))"
        }
    }

    @MainActor func stageDocuments(_ urls: [URL]) async {
        messageActionError = nil
        do {
            try await composer.stageDocuments(urls)
        } catch {
            messageActionError = "File couldn't be prepared: \(telegramErrorDescription(error))"
        }
    }

    @MainActor func appendStagedDocuments(_ urls: [URL]) async {
        messageActionError = nil
        do {
            try await composer.appendStagedDocuments(urls)
        } catch {
            messageActionError = "File couldn't be prepared: \(telegramErrorDescription(error))"
        }
    }

    func setShowSendButton() { composer.setShowSendButton() }
    func setEditMessageText(from message: Message?) { composer.setEditMessageText(from: message) }
    func updateDraft() async { await composer.updateDraft() }
    func startTimer() { voiceRecorder.startTimer() }
    func stopTimer() { voiceRecorder.stopTimer() }
    func mediaStartRecordingVoice() async { await voiceRecorder.mediaStartRecordingVoice() }
    func cancelRecordingVoice() { voiceRecorder.cancelRecordingVoice() }
    func mediaStartRecordingVideo() async {
        Media.shared.stop()
        TelegramAudioPlayer.shared.stop()
        TelegramVideoNotePlayer.shared.stop()
        await videoRecorder.start { [weak self] artifact, schedulingState in
            guard let self else { return }
            Task {
                do {
                    try await composer.sendMessageVideoNote(
                        artifact: artifact,
                        schedulingState: schedulingState,
                    )
                } catch {
                    guard !Task.isCancelled else { return }
                    messageActionError = "Video message couldn't be sent: \(telegramErrorDescription(error))"
                }
            }
        }
        if videoRecorder.isRecording {
            _ = try? await service.sendChatAction(
                action: .chatActionRecordingVideoNote,
                businessConnectionId: nil,
                chatId: chatId,
                topicId: messageTopic,
            )
        }
    }

    func cancelRecordingVideo() {
        videoRecorder.cancel()
        Task {
            _ = try? await service.sendChatAction(
                action: .chatActionCancel,
                businessConnectionId: nil,
                chatId: chatId,
                topicId: messageTopic,
            )
        }
    }

    func pauseRecordingVideo() {
        videoRecorder.pause()
        Task {
            _ = try? await service.sendChatAction(
                action: .chatActionCancel,
                businessConnectionId: nil,
                chatId: chatId,
                topicId: messageTopic,
            )
        }
    }

    func resumeRecordingVideo() {
        videoRecorder.resume()
        guard videoRecorder.isRecording else { return }
        Task {
            _ = try? await service.sendChatAction(
                action: .chatActionRecordingVideoNote,
                businessConnectionId: nil,
                chatId: chatId,
                topicId: messageTopic,
            )
        }
    }

    func mediaStopRecordingVideo(schedulingState: MessageSchedulingState? = nil) {
        videoRecorder.stop(schedulingState: schedulingState)
        Task {
            _ = try? await service.sendChatAction(
                action: .chatActionCancel,
                businessConnectionId: nil,
                chatId: chatId,
                topicId: messageTopic,
            )
        }
    }

    func mediaStopRecordingVoice(duration: Int, wave: [Float], schedulingState: MessageSchedulingState? = nil) {
        guard let artifact = voiceRecorder.mediaStopRecordingVoice(duration: duration, wave: wave) else { return }
        Task.background {
            do {
                try await self.composer.sendMessageVoiceNote(
                    url: artifact.url,
                    duration: artifact.duration,
                    waveform: artifact.waveform,
                    isViewOnce: artifact.isViewOnce,
                    schedulingState: schedulingState,
                )
            } catch {
                guard !Task.isCancelled else { return }
                await main {
                    self.messageActionError =
                        "Voice message couldn't be sent: \(telegramErrorDescription(error))"
                }
            }
        }
    }
}
