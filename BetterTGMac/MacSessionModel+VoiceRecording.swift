// MacSessionModel+VoiceRecording.swift

import AVFoundation
import Foundation
import TDLibKit

extension MacSessionModel {
    func startVoiceRecording() async {
        guard !isRecordingVoice, selectedDocumentURLs.isEmpty, selectedPhotoURLs.isEmpty,
              editingMessage == nil, let openedChatId
        else { return }
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            messageActionError = "Microphone access is required to record a voice message."
            return
        }

        MacVoicePlayer.shared.stop()
        let url = TelegramVoiceNoteSending.temporaryFileURL()
        let recorder = VoiceNoteRecorder()
        do {
            try recorder.start()
        } catch {
            messageActionError = "Voice recording could not start: \(error.localizedDescription)"
            return
        }

        voiceRecorder = recorder
        voiceRecordingURL = url
        voiceRecordingChatId = openedChatId
        voiceRecordingStartedAt = Foundation.Date()
        voiceRecordingDuration = 0
        voiceRecordingWave = []
        isRecordingVoice = true
        recordingTimer?.cancel()
        recordingTimer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard let self, isRecordingVoice, let startedAt = voiceRecordingStartedAt else { return }
                voiceRecordingDuration = Foundation.Date().timeIntervalSince(startedAt)
                voiceRecordingWave.append(voiceRecorder?.currentPeakPower() ?? -160)
            }
        }

        _ = try? await service.sendChatAction(
            action: .chatActionRecordingVoiceNote,
            businessConnectionId: nil,
            chatId: openedChatId,
            topicId: openedTopic,
        )
    }

    func cancelVoiceRecording() {
        guard isRecordingVoice || voiceRecorder != nil else { return }
        let chatId = voiceRecordingChatId
        let url = voiceRecordingURL
        voiceRecorder?.cancel()
        resetVoiceRecordingState()
        if let url {
            TelegramOutgoingFileStaging.shared.discard(fileURL: url)
        }
        if let chatId {
            let topicId = openedChatId == chatId ? openedTopic : nil
            Task {
                _ = try? await service.sendChatAction(
                    action: .chatActionCancel,
                    businessConnectionId: nil,
                    chatId: chatId,
                    topicId: topicId,
                )
            }
        }
    }

    func sendVoiceRecording(schedulingState: MessageSchedulingState? = nil) {
        guard !isSubmittingMessage,
              let recorder = voiceRecorder,
              let url = voiceRecordingURL,
              let chatId = voiceRecordingChatId,
              openedChatId == chatId
        else {
            cancelVoiceRecording()
            return
        }

        let duration: Int
        do {
            duration = try max(1, Int(ceil(recorder.stopAndWrite(to: url))))
        } catch {
            messageActionError = "Voice recording could not be finalized: \(error.localizedDescription)"
            cancelVoiceRecording()
            return
        }

        let waveform = TelegramVoiceNoteSending.waveform(from: voiceRecordingWave)
        let replyTo = TelegramMessageSending.replyTo(messageId: replyingToMessage?.id)
        let replyMessageId = replyingToMessage?.id
        let topicId = openedTopic
        resetVoiceRecordingState()
        messageActionError = nil
        isSubmittingMessage = true

        Task {
            defer { isSubmittingMessage = false }
            do {
                try await TelegramVoiceNoteSending.send(
                    service: service,
                    chatId: chatId,
                    url: url,
                    caption: FormattedText(entities: [], text: ""),
                    duration: duration,
                    waveform: waveform,
                    replyTo: replyTo,
                    schedulingState: schedulingState,
                    topicId: topicId,
                )
                clearDraft(chatId: chatId)
                guard openedChatId == chatId, replyingToMessage?.id == replyMessageId else { return }
                replyingToMessage = nil
            } catch {
                guard !Task.isCancelled else { return }
                messageActionError = "Voice message couldn't be sent: \(telegramErrorDescription(error))"
            }
        }
    }

    // MARK: Private

    private func resetVoiceRecordingState() {
        recordingTimer?.cancel()
        recordingTimer = nil
        voiceRecorder = nil
        voiceRecordingURL = nil
        voiceRecordingChatId = nil
        voiceRecordingStartedAt = nil
        voiceRecordingDuration = 0
        voiceRecordingWave = []
        isRecordingVoice = false
    }
}
