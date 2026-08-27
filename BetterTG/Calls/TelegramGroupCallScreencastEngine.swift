// TelegramGroupCallScreencastEngine.swift

import Foundation
@preconcurrency import TgVoipWebrtc

// MARK: - TelegramGroupCallScreencastEngine

/// Owns the second tgcalls context used exclusively for conference screen sharing. Telegram-iOS
/// deliberately keeps this transport separate from the main camera/audio context.
final class TelegramGroupCallScreencastEngine: @unchecked Sendable {
    // MARK: Lifecycle

    init() {
        self.contextQueue = CallContextQueue(queue: queue)
    }

    // MARK: Internal

    func start(
        capturer: OngoingCallThreadLocalContextVideoCapturer,
        encryption: TelegramGroupCallEngine.Encryption,
        joinPayloadReady: @escaping @Sendable (_ payload: String, _ audioSourceId: Int) -> Void,
    ) {
        queue.async { [weak self] in
            guard let self else { return }
            stopLocked()
            let generation = UUID()
            self.generation = generation
            let audioDevice = SharedCallAudioDevice(
                disableRecording: true,
                enableSystemMute: false,
            )
            let context = GroupCallThreadLocalContext(
                queue: contextQueue,
                networkStateUpdated: { _ in },
                audioLevelsUpdated: { _ in },
                activityUpdated: { _ in },
                inputDeviceId: "",
                outputDeviceId: "",
                videoCapturer: capturer,
                requestMediaChannelDescriptions: { _, completion in
                    completion([])
                    return ScreencastMediaChannelTask()
                },
                requestCurrentTime: { completion in
                    completion(0)
                    return ScreencastBroadcastPartTask()
                },
                requestAudioBroadcastPart: { _, _, completion in
                    completion(nil)
                    return ScreencastBroadcastPartTask()
                },
                requestVideoBroadcastPart: { _, _, _, _, completion in
                    completion(nil)
                    return ScreencastBroadcastPartTask()
                },
                outgoingAudioBitrateKbit: 32,
                videoContentType: .screencast,
                enableNoiseSuppression: false,
                disableAudioInput: true,
                enableSystemMute: false,
                prioritizeVP8: false,
                logPath: "",
                statsLogPath: "",
                onMutedSpeechActivityDetected: nil,
                audioDevice: audioDevice,
                isConference: true,
                isActiveByDefault: true,
                encryptDecrypt: { data, userId, isEncrypt, unencryptedPrefixSize in
                    if isEncrypt {
                        encryption.encrypt(data, unencryptedPrefixSize)
                    } else {
                        encryption.decrypt(data, userId)
                    }
                },
                useReferenceImpl: false,
            )
            self.audioDevice = audioDevice
            self.context = context
            context.setManualAudioSessionIsActive(true)
            context.emitJoinPayload { [weak self] payload, sourceId in
                guard let self, self.generation == generation else { return }
                joinPayloadReady(payload, Int(sourceId))
            }
        }
    }

    func applyJoinResponse(_ payload: String) {
        queue.async { [weak self] in
            guard let context = self?.context else { return }
            context.setConnectionMode(
                .rtc,
                keepBroadcastConnectedIfWasEnabled: false,
                isUnifiedBroadcast: false,
            )
            context.setJoinResponsePayload(payload)
        }
    }

    func addExternalAudioData(_ data: Data) {
        queue.async { [weak self] in
            self?.context?.addExternalAudioData(data)
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.stopLocked()
        }
    }

    // MARK: Private

    private let queue = DispatchQueue(label: "com.gruiachiscop.BetterTG.group-call-screencast")
    private let contextQueue: CallContextQueue
    private var context: GroupCallThreadLocalContext?
    private var audioDevice: SharedCallAudioDevice?
    private var generation = UUID()

    private func stopLocked() {
        generation = UUID()
        guard let context else {
            audioDevice = nil
            return
        }
        self.context = nil
        context.stop { [weak self] in
            guard let self else { return }
            queue.async { [self] in
                audioDevice = nil
            }
        }
    }
}

// MARK: - ScreencastMediaChannelTask

private final class ScreencastMediaChannelTask: NSObject, OngoingGroupCallMediaChannelDescriptionTask {
    func cancel() {}
}

// MARK: - ScreencastBroadcastPartTask

private final class ScreencastBroadcastPartTask: NSObject, OngoingGroupCallBroadcastPartTask {
    func cancel() {}
}
