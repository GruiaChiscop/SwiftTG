// TelegramGroupCallEngine.swift

import Foundation
@preconcurrency import TgVoipWebrtc
import UIKit

// MARK: - TelegramGroupCallEngine

/// Owns the tgcalls context used by standalone encrypted group calls. All mutable state and every
/// tgcalls call are confined to `queue`, matching the contract used by Telegram-iOS.
final class TelegramGroupCallEngine: @unchecked Sendable {
    // MARK: Lifecycle

    init() {
        self.contextQueue = CallContextQueue(queue: queue)
    }

    // MARK: Internal

    struct Encryption: Sendable {
        let encrypt: @Sendable (_ data: Data, _ unencryptedPrefixSize: Int32) -> Data?
        let decrypt: @Sendable (_ data: Data, _ userId: Int64) -> Data?
    }

    struct MediaChannel: Equatable, Sendable {
        let audioSourceId: UInt32
        let peerId: Int64
    }

    struct VideoChannel: Equatable, Sendable {
        struct SourceGroup: Equatable, Sendable {
            let semantics: String
            let sourceIds: [UInt32]
        }

        let audioSourceId: UInt32
        let peerId: Int64
        let endpointId: String
        let sourceGroups: [SourceGroup]
        let isScreenSharing: Bool
    }

    struct NetworkState: Equatable, Sendable {
        let isConnected: Bool
        let isTransitioningFromBroadcastToRtc: Bool
    }

    struct AudioLevel: Equatable, Sendable {
        let audioSourceId: UInt32
        let level: Float
        let hasVoice: Bool
    }

    struct Configuration: Sendable {
        let encryption: Encryption
        let isActiveByDefault: Bool
        let isMuted: Bool
        let outgoingAudioBitrateKbit: Int32?
        let prioritizeVP8: Bool
        let useReferenceImpl: Bool
        let logPath: String
        let statsLogPath: String
    }

    func prepareJoin(
        configuration: Configuration,
        sharedAudioDevice: SharedCallAudioDevice?,
        audioSessionActive: Bool,
        joinPayloadReady: @escaping @Sendable (_ payload: String, _ audioSourceId: Int) -> Void,
        networkStateChanged: @escaping @Sendable (NetworkState) -> Void,
        audioLevelsChanged: @escaping @Sendable ([AudioLevel]) -> Void,
        signalBarsChanged: @escaping @Sendable (Int32) -> Void,
    ) {
        queue.async { [weak self] in
            guard let self else { return }

            stopLocked()
            let generation = UUID()
            self.generation = generation

            let audioDevice = sharedAudioDevice ?? SharedCallAudioDevice(
                disableRecording: false,
                enableSystemMute: false,
            )
            let context = GroupCallThreadLocalContext(
                queue: contextQueue,
                networkStateUpdated: { [weak self] state in
                    guard let self, self.generation == generation else { return }
                    networkStateChanged(NetworkState(
                        isConnected: state.isConnected,
                        isTransitioningFromBroadcastToRtc: state.isTransitioningFromBroadcastToRtc,
                    ))
                },
                audioLevelsUpdated: { [weak self] values in
                    guard let self, self.generation == generation else { return }
                    var levels = [AudioLevel]()
                    levels.reserveCapacity(values.count / 3)
                    for index in stride(from: 0, to: values.count - 2, by: 3) {
                        levels.append(AudioLevel(
                            audioSourceId: values[index].uint32Value,
                            level: values[index + 1].floatValue,
                            hasVoice: values[index + 2].boolValue,
                        ))
                    }
                    audioLevelsChanged(levels)
                },
                activityUpdated: { _ in },
                inputDeviceId: "",
                outputDeviceId: "",
                videoCapturer: nil,
                requestMediaChannelDescriptions: { [weak self] sourceIds, completion in
                    guard let self else {
                        completion([])
                        return GroupCallMediaChannelTask()
                    }
                    let descriptions = sourceIds.compactMap { sourceId -> OngoingGroupCallMediaChannelDescription? in
                        guard let channel = self.mediaChannels[sourceId.uint32Value] else { return nil }
                        return OngoingGroupCallMediaChannelDescription(
                            type: .audio,
                            peerId: channel.peerId,
                            audioSsrc: channel.audioSourceId,
                            videoDescription: nil,
                        )
                    }
                    completion(descriptions)
                    return GroupCallMediaChannelTask()
                },
                requestCurrentTime: { completion in
                    completion(0)
                    return GroupCallBroadcastPartTask()
                },
                requestAudioBroadcastPart: { _, _, completion in
                    completion(nil)
                    return GroupCallBroadcastPartTask()
                },
                requestVideoBroadcastPart: { _, _, _, _, completion in
                    completion(nil)
                    return GroupCallBroadcastPartTask()
                },
                outgoingAudioBitrateKbit: configuration.outgoingAudioBitrateKbit ?? 32,
                videoContentType: .none,
                enableNoiseSuppression: false,
                disableAudioInput: false,
                enableSystemMute: false,
                prioritizeVP8: configuration.prioritizeVP8,
                logPath: configuration.logPath,
                statsLogPath: configuration.statsLogPath,
                onMutedSpeechActivityDetected: nil,
                audioDevice: audioDevice,
                isConference: true,
                isActiveByDefault: configuration.isActiveByDefault,
                encryptDecrypt: { data, userId, isEncrypt, unencryptedPrefixSize in
                    if isEncrypt {
                        configuration.encryption.encrypt(data, unencryptedPrefixSize)
                    } else {
                        configuration.encryption.decrypt(data, userId)
                    }
                },
                useReferenceImpl: configuration.useReferenceImpl,
            )
            context.signalBarsChanged = { [weak self] value in
                guard let self, self.generation == generation else { return }
                signalBarsChanged(value)
            }

            self.audioDevice = audioDevice
            self.context = context
            context.setIsMuted(configuration.isMuted)
            context.setManualAudioSessionIsActive(audioSessionActive)
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

    func emitJoinPayload(
        completion: @escaping @Sendable (_ payload: String, _ audioSourceId: Int) -> Void,
    ) {
        queue.async { [weak self] in
            guard let self, let context else { return }
            let requestGeneration = generation
            context.emitJoinPayload { [weak self] payload, sourceId in
                guard let self, generation == requestGeneration else { return }
                completion(payload, Int(sourceId))
            }
        }
    }

    func updateMediaChannels(_ channels: [MediaChannel]) {
        queue.async { [weak self] in
            self?.mediaChannels = Dictionary(uniqueKeysWithValues: channels.map { ($0.audioSourceId, $0) })
        }
    }

    func updateRequestedVideoChannels(
        _ channels: [VideoChannel],
        maximumQuality: ConferenceIncomingVideoQuality,
    ) {
        queue.async { [weak self] in
            guard let self else { return }
            requestedVideoChannels = channels
            let requestedChannels = maximumQuality == .audioOnly ? [] : channels
            let maximumEngineQuality: OngoingGroupCallRequestedVideoQuality =
                switch maximumQuality {
                case .audioOnly, .p180: .thumbnail
                case .p360: .medium
                case .p720: .full
                }
            context?.setRequestedVideoChannels(requestedChannels.map { channel in
                OngoingGroupCallRequestedVideoChannel(
                    audioSsrc: channel.audioSourceId,
                    userId: channel.peerId,
                    endpointId: channel.endpointId,
                    ssrcGroups: channel.sourceGroups.map { group in
                        OngoingGroupCallSsrcGroup(
                            semantics: group.semantics,
                            ssrcs: group.sourceIds.map { NSNumber(value: $0) },
                        )
                    },
                    minQuality: .thumbnail,
                    maxQuality: maximumEngineQuality,
                )
            })
        }
    }

    func makeIncomingVideoView(
        endpointId: String,
        completion: @escaping @MainActor (UIView?) -> Void,
    ) {
        queue.async { [weak self] in
            guard let context = self?.context else {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }
            context.makeIncomingVideoView(
                withEndpointId: endpointId,
                requestClone: false,
            ) { videoView, _ in
                DispatchQueue.main.async {
                    completion(videoView)
                }
            }
        }
    }

    func requestVideo(
        _ capturer: OngoingCallThreadLocalContextVideoCapturer,
        joinPayloadReady: @escaping @Sendable (_ payload: String, _ audioSourceId: Int) -> Void,
    ) {
        queue.async { [weak self] in
            guard let self, let context else { return }
            let requestGeneration = generation
            context.requestVideo(capturer) { [weak self] payload, sourceId in
                guard let self, generation == requestGeneration else { return }
                joinPayloadReady(payload, Int(sourceId))
            }
        }
    }

    func disableVideo(
        joinPayloadReady: @escaping @Sendable (_ payload: String, _ audioSourceId: Int) -> Void,
    ) {
        queue.async { [weak self] in
            guard let self, let context else { return }
            let requestGeneration = generation
            context.disableVideo { [weak self] payload, sourceId in
                guard let self, generation == requestGeneration else { return }
                joinPayloadReady(payload, Int(sourceId))
            }
        }
    }

    func setMuted(_ muted: Bool) {
        queue.async { [weak self] in
            self?.context?.setIsMuted(muted)
        }
    }

    func setVolume(audioSourceId: UInt32, volume: Double) {
        queue.async { [weak self] in
            self?.context?.setVolumeForSsrc(audioSourceId, volume: volume)
        }
    }

    func setAudioSessionActive(_ active: Bool) {
        queue.async { [weak self] in
            self?.context?.setManualAudioSessionIsActive(active)
        }
    }

    func activateIncomingAudio() {
        queue.async { [weak self] in
            self?.context?.activateIncomingAudio()
        }
    }

    func stop(completion: (@Sendable () -> Void)? = nil) {
        queue.async { [weak self] in
            guard let self else {
                completion?()
                return
            }
            stopLocked(completion: completion)
        }
    }

    // MARK: Private

    private let queue = DispatchQueue(label: "com.gruiachiscop.BetterTG.group-call-engine")
    private let contextQueue: CallContextQueue
    private var context: GroupCallThreadLocalContext?
    private var audioDevice: SharedCallAudioDevice?
    private var mediaChannels = [UInt32: MediaChannel]()
    private var requestedVideoChannels = [VideoChannel]()
    private var generation = UUID()

    private func stopLocked(completion: (@Sendable () -> Void)? = nil) {
        generation = UUID()
        let stopGeneration = generation
        mediaChannels.removeAll(keepingCapacity: false)
        requestedVideoChannels.removeAll(keepingCapacity: false)
        guard let context else {
            audioDevice = nil
            completion?()
            return
        }
        self.context = nil
        context.stop { [weak self] in
            guard let self else {
                completion?()
                return
            }
            queue.async { [self] in
                if generation == stopGeneration {
                    audioDevice = nil
                }
                completion?()
            }
        }
    }
}

// MARK: - GroupCallMediaChannelTask

private final class GroupCallMediaChannelTask: NSObject, OngoingGroupCallMediaChannelDescriptionTask {
    func cancel() {}
}

// MARK: - GroupCallBroadcastPartTask

private final class GroupCallBroadcastPartTask: NSObject, OngoingGroupCallBroadcastPartTask {
    func cancel() {}
}
