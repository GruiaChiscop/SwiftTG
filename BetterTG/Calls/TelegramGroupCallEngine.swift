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

    enum RequestedVideoQuality: Sendable {
        case thumbnail
        case medium
        case full
    }

    struct BroadcastPart: Sendable {
        let timestampMilliseconds: Int64
        /// Wall-clock time the segment was produced, in **seconds** - tgcalls reads this field in
        /// seconds while every other value in this API is milliseconds.
        let responseTimeSeconds: Double
        let oggData: Data
    }

    /// Pulls HLS-style stream segments for a chat-bound video chat / live stream while the tgcalls
    /// connection is in broadcast mode. `nil` on `Configuration` for an E2E conference (always RTC).
    struct BroadcastDataSource: Sendable {
        /// Current stream time in ms - wall clock for a normal broadcast, the stream's `time_offset`
        /// for an RTMP live stream.
        let currentTimeMilliseconds: @Sendable () async -> Int64
        let audioPart: @Sendable (_ timestampMilliseconds: Int64, _ durationMilliseconds: Int64) async -> BroadcastPart?
        let videoPart: @Sendable (
            _ timestampMilliseconds: Int64,
            _ durationMilliseconds: Int64,
            _ channelId: Int32,
            _ quality: RequestedVideoQuality,
        ) async -> BroadcastPart?
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
        /// End-to-end frame encryption. `nil` for a plain (server-mixed) video chat, which is not
        /// E2E - tgcalls then installs no frame transformer and takes audio levels from the network.
        let encryption: Encryption?
        /// `true` for an E2E conference call, `false` for a chat-bound video chat.
        let isConference: Bool
        /// Segment source for broadcast mode. `nil` for E2E conferences (which stay RTC).
        let broadcast: BroadcastDataSource?
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
                    guard let broadcast = configuration.broadcast else {
                        completion(0)
                        return GroupCallBroadcastPartTask()
                    }
                    let task = GroupCallBroadcastPartTask()
                    let completion = GroupCallSendableCompletion(completion)
                    task.run {
                        let time = await broadcast.currentTimeMilliseconds()
                        if !Task.isCancelled {
                            completion.call(time)
                        }
                    }
                    return task
                },
                requestAudioBroadcastPart: { timestampMs, durationMs, completion in
                    guard let broadcast = configuration.broadcast else {
                        completion(nil)
                        return GroupCallBroadcastPartTask()
                    }
                    let task = GroupCallBroadcastPartTask()
                    let completion = GroupCallSendableCompletion(completion)
                    task.run {
                        let part = await broadcast.audioPart(timestampMs, durationMs)
                        if !Task.isCancelled {
                            completion.call(Self.broadcastPart(part, requestedTimestampMs: timestampMs))
                        }
                    }
                    return task
                },
                requestVideoBroadcastPart: { timestampMs, durationMs, channelId, quality, completion in
                    guard let broadcast = configuration.broadcast else {
                        completion(nil)
                        return GroupCallBroadcastPartTask()
                    }
                    let mappedQuality = Self.requestedVideoQuality(from: quality)
                    let task = GroupCallBroadcastPartTask()
                    let completion = GroupCallSendableCompletion(completion)
                    task.run {
                        let part = await broadcast.videoPart(timestampMs, durationMs, channelId, mappedQuality)
                        if !Task.isCancelled {
                            completion.call(Self.broadcastPart(part, requestedTimestampMs: timestampMs))
                        }
                    }
                    return task
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
                isConference: configuration.isConference,
                isActiveByDefault: configuration.isActiveByDefault,
                encryptDecrypt: configuration.encryption.map { encryption in
                    { data, userId, isEncrypt, unencryptedPrefixSize in
                        isEncrypt
                            ? encryption.encrypt(data, unencryptedPrefixSize)
                            : encryption.decrypt(data, userId)
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
        let selectsBroadcast = Self.joinResponseSelectsBroadcast(payload)
        queue.async { [weak self] in
            guard let context = self?.context else { return }
            context.setConnectionMode(
                selectsBroadcast ? .broadcast : .rtc,
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
        centralEndpointId: String?,
        hasCentralVideo: Bool,
    ) {
        queue.async { [weak self] in
            guard let self else { return }
            requestedVideoChannels = channels
            let requestedChannels = maximumQuality == .audioOnly ? [] : channels
            context?.setRequestedVideoChannels(requestedChannels.map { channel in
                let maximumEngineQuality: OngoingGroupCallRequestedVideoQuality =
                    switch maximumQuality {
                    case .audioOnly, .p180:
                        .thumbnail
                    case .p360:
                        hasCentralVideo && channel.endpointId != centralEndpointId ? .thumbnail : .medium
                    case .p720:
                        if hasCentralVideo {
                            channel.endpointId == centralEndpointId ? .full : .thumbnail
                        } else {
                            .medium
                        }
                    }
                return OngoingGroupCallRequestedVideoChannel(
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

    private static func broadcastPart(
        _ part: BroadcastPart?,
        requestedTimestampMs: Int64,
    ) -> OngoingGroupCallBroadcastPart {
        guard let part else {
            return OngoingGroupCallBroadcastPart(
                timestampMilliseconds: requestedTimestampMs,
                responseTimestamp: Date().timeIntervalSince1970,
                status: .notReady,
                oggData: Data(),
            )
        }
        return OngoingGroupCallBroadcastPart(
            timestampMilliseconds: part.timestampMilliseconds,
            responseTimestamp: part.responseTimeSeconds,
            status: .success,
            oggData: part.oggData,
        )
    }

    private static func requestedVideoQuality(
        from quality: OngoingGroupCallRequestedVideoQuality,
    ) -> RequestedVideoQuality {
        switch quality {
        case .thumbnail: .thumbnail
        case .medium: .medium
        case .full: .full
        @unknown default: .thumbnail
        }
    }

    private static func joinResponseSelectsBroadcast(_ payload: String) -> Bool {
        guard let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }
        return object["stream"] as? Bool ?? false
    }

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

// MARK: - GroupCallSendableCompletion

/// The Objective-C tgcalls protocol predates Swift concurrency and doesn't annotate its completion
/// handlers as Sendable. This one-shot box synchronizes ownership while the callback crosses into
/// the async broadcast task.
private final class GroupCallSendableCompletion<Value>: @unchecked Sendable {
    // MARK: Lifecycle

    init(_ completion: @escaping (Value) -> Void) {
        self.completion = completion
    }

    // MARK: Internal

    func call(_ value: Value) {
        let completion = lock.withLock {
            let completion = self.completion
            self.completion = nil
            return completion
        }
        completion?(value)
    }

    // MARK: Private

    private let lock = NSLock()
    private var completion: ((Value) -> Void)?
}

// MARK: - GroupCallMediaChannelTask

private final class GroupCallMediaChannelTask: NSObject, OngoingGroupCallMediaChannelDescriptionTask {
    func cancel() {}
}

// MARK: - GroupCallBroadcastPartTask

/// tgcalls asks for a stream segment synchronously and expects a cancellable handle back; the fetch
/// itself is an async TDLib call, so the work runs in a `Task` this handle can cancel.
private final class GroupCallBroadcastPartTask: NSObject, OngoingGroupCallBroadcastPartTask, @unchecked Sendable {
    // MARK: Internal

    func run(_ operation: @escaping @Sendable () async -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !isCancelled else { return }
        task = Task(operation: operation)
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        isCancelled = true
        task?.cancel()
        task = nil
    }

    // MARK: Private

    private let lock = NSLock()
    private var task: Task<Void, Never>?
    private var isCancelled = false
}
