// VoiceRecordingController.swift

import AVKit
import SwiftUI
import TDLibKit

/// Lifecycle of recording an outgoing voice note (timer, waveform, recorder). Split out of
/// `ChatVM`, which composes this alongside `MessageComposer` and hands the finished recording's
/// artifact back to `ChatVM.mediaStopRecordingVoice(duration:wave:)` for sending.
@Observable final class VoiceRecordingController {
    // MARK: Lifecycle

    init(chatId: Int64, service: any TelegramService) {
        self.chatId = chatId
        self.service = service
    }

    // MARK: Internal

    var recordingVoiceNote = false
    var recordingLocked = false
    var recordingDragTranslation = CGSize.zero
    var errorShown = false
    var timerCount = 0.0
    @ObservationIgnored var wave = [Float]()

    var formattedTimerCount: String {
        telegramClockDuration(Int(timerCount))
    }

    func startTimer() {
        let timer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { [weak self] timer in
            guard let self, let audioRecorder else { return }
            wave.append(audioRecorder.peakPower)
            timerCount += timer.timeInterval
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stopTimer() {
        timer?.invalidate()
        timer = nil
        timerCount = 0
    }

    @MainActor func mediaStartRecordingVoice() async {
        Media.shared.stop()
        Media.shared.setAudioSessionRecord()

        let granted = await AVAudioApplication.requestRecordPermission()
        if granted {
            log("Access to Microphone for Voice messages is granted")
        } else {
            log("Access to Microphone for Voice messages is not granted")
            errorShown = true
            return
        }

        let url = TelegramVoiceNoteSending.temporaryFileURL()
        savedVoiceNoteUrl = url

        do {
            let recorder = VoiceNoteRecorder()
            try recorder.start()
            audioRecorder = recorder
            withAnimation {
                recordingVoiceNote = true
                recordingLocked = false
                recordingDragTranslation = .zero
            }
            try? await tdSendChatAction(.chatActionRecordingVoiceNote)
        } catch {
            log("Error creating AudioRecorder: \(error)")
        }
    }

    func cancelRecordingVoice() {
        audioRecorder?.cancel()
        audioRecorder = nil
        TelegramOutgoingFileStaging.shared.discard(fileURL: savedVoiceNoteUrl)
        withAnimation {
            recordingVoiceNote = false
            recordingLocked = false
            recordingDragTranslation = .zero
        }
        Task.background { try? await self.tdSendChatAction(.chatActionCancel) }
    }

    /// Finalizes the in-progress recording and returns its artifact for `ChatVM` to send, or
    /// `nil` if finalizing failed (in which case this already self-cancels and cleans up).
    func mediaStopRecordingVoice(duration: Int, wave: [Float]) -> (url: URL, duration: Int, waveform: Data)? {
        guard let audioRecorder else { return nil }
        let encodedDuration: Int
        do {
            encodedDuration = try Int(ceil(audioRecorder.stopAndWrite(to: savedVoiceNoteUrl)))
        } catch {
            log("Error finalizing voice note:", error)
            cancelRecordingVoice()
            return nil
        }
        self.audioRecorder = nil
        withAnimation {
            recordingVoiceNote = false
            recordingLocked = false
            recordingDragTranslation = .zero
        }
        Task.background { try? await self.tdSendChatAction(.chatActionCancel) }

        let waveform = TelegramVoiceNoteSending.waveform(from: wave)
        return (url: savedVoiceNoteUrl, duration: max(encodedDuration, duration), waveform: waveform)
    }

    // MARK: Private

    private let chatId: Int64
    private let service: any TelegramService

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var savedVoiceNoteUrl = URL(filePath: "")
    @ObservationIgnored private var audioRecorder: VoiceNoteRecorder?

    private func tdSendChatAction(_ chatAction: ChatAction) async throws {
        _ = try await service.sendChatAction(
            action: chatAction,
            businessConnectionId: nil,
            chatId: chatId,
            topicId: nil,
        )
    }
}
