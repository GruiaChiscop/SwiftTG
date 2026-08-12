// MacSessionModel+VideoRecording.swift

import Foundation
import TDLibKit

extension MacSessionModel {
    func startVideoRecording() async {
        guard !isRecordingVoice,
              !videoRecorder.isPreparing,
              !videoRecorder.isRecording,
              !videoRecorder.isPaused,
              !videoRecorder.isFinalizing,
              selectedDocumentURLs.isEmpty,
              selectedPhotoURLs.isEmpty,
              editingMessage == nil,
              let chatId = openedChatId
        else { return }

        MacVoicePlayer.shared.stop()
        TelegramAudioPlayer.shared.stop()
        TelegramVideoNotePlayer.shared.stop()
        let replyMessageId = replyingToMessage?.id
        let topicId = openedTopic
        let allowsLiveUpload =
            if case .some(.chatTypeSecret) = openedChatType {
                false
            } else {
                true
            }
        await videoRecorder.start(
            service: service,
            allowsLiveUpload: allowsLiveUpload,
        ) { [weak self] artifact, deliveryOptions in
            guard let self else { return }
            isSubmittingMessage = true
            messageActionError = nil
            Task {
                defer { isSubmittingMessage = false }
                do {
                    try await TelegramVideoNoteSending.send(
                        service: service,
                        chatId: chatId,
                        url: artifact.url,
                        thumbnail: artifact.thumbnail,
                        preliminaryUploadFileId: artifact.preliminaryUploadFileId,
                        duration: artifact.duration,
                        length: artifact.length,
                        isViewOnce: artifact.isViewOnce,
                        replyTo: TelegramMessageSending.replyTo(messageId: replyMessageId),
                        schedulingState: deliveryOptions.schedulingState,
                        disableNotification: deliveryOptions.disableNotification,
                        effectId: deliveryOptions.effectId,
                        topicId: topicId,
                    )
                    clearDraft(chatId: chatId)
                    guard openedChatId == chatId, replyingToMessage?.id == replyMessageId else { return }
                    replyingToMessage = nil
                } catch {
                    guard !Task.isCancelled else { return }
                    messageActionError = "Video message couldn't be sent: \(telegramErrorDescription(error))"
                }
            }
        }
        if let error = videoRecorder.errorMessage {
            messageActionError = error
            videoRecorder.clearError()
        } else if videoRecorder.isRecording {
            _ = try? await service.sendChatAction(
                action: .chatActionRecordingVideoNote,
                businessConnectionId: nil,
                chatId: chatId,
                topicId: topicId,
            )
        }
    }

    func cancelVideoRecording() {
        videoRecorder.cancel()
        cancelVideoRecordingChatAction()
    }

    func toggleVideoRecordingPause() async {
        if videoRecorder.isPaused {
            await videoRecorder.resume()
            guard videoRecorder.isRecording, let chatId = openedChatId else { return }
            let topicId = openedTopic
            Task {
                _ = try? await service.sendChatAction(
                    action: .chatActionRecordingVideoNote,
                    businessConnectionId: nil,
                    chatId: chatId,
                    topicId: topicId,
                )
            }
        } else {
            videoRecorder.pause()
            cancelVideoRecordingChatAction()
        }
    }

    func sendVideoRecording(
        schedulingState: MessageSchedulingState? = nil,
        disableNotification: Bool = false,
        effectId: TdInt64 = 0,
    ) {
        videoRecorder.stop(
            schedulingState: schedulingState,
            disableNotification: disableNotification,
            effectId: effectId,
        )
        cancelVideoRecordingChatAction()
    }

    private func cancelVideoRecordingChatAction() {
        guard let chatId = openedChatId else { return }
        let topicId = openedTopic
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
