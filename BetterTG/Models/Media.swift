// Media.swift

import AVFoundation
import MediaPlayer
import Observation
import SwiftOGG

@Observable final class Media {
    // MARK: Lifecycle

    init() {
        setCommandCenterControls()
    }

    // MARK: Internal

    static let shared = Media()

    var savedMediaPath = ""
    var isPlaying = false
    var currentTime: Int32 = 0

    func stop() {
        playbackGeneration &+= 1
        isPlaying = false
        currentTime = 0
        savedMediaPath = ""
        stopProgressTimer()
        playerNode.stop()
        audioBuffer = nil
        nowPlayingCenter.nowPlayingInfo = nil
    }

    func onChatOpen(title: String) {
        self.title = title
    }

    func onChatDismiss() {
        playerNode.pause()
        isPlaying = false
        stopProgressTimer()
    }

    func seekForward() {
        seekTo(playerTime + 5)
    }

    func seekBackward() {
        seekTo(max(0, playerTime - 5))
    }

    func toggle(with path: String, duration: Int) {
        self.duration = duration
        if savedMediaPath != path {
            stop()
            savedMediaPath = path
            preparePlayer(for: path)
        } else {
            toggle()
        }
    }

    func setAudioSessionRecord() {
        do {
            try audioSession.setActive(false)
            try audioSession.setCategory(.playAndRecord, mode: .default, policy: .default, options: [
                .allowAirPlay,
                .allowBluetoothHFP,
                .allowBluetoothA2DP,
                .defaultToSpeaker,
                .overrideMutedMicrophoneInterruption,
            ])
            try audioSession.setActive(true)
        } catch {
            log("Error setting audioSessionRecord: \(error)")
        }
    }

    // MARK: Private

    private enum PlaybackError: Error { case invalidPCM }

    @ObservationIgnored private var duration = 0
    @ObservationIgnored private var title = ""

    @ObservationIgnored private let playbackEngine = AVAudioEngine()
    @ObservationIgnored private let playerNode = AVAudioPlayerNode()
    @ObservationIgnored private var audioBuffer: AVAudioPCMBuffer?
    @ObservationIgnored private var scheduledBuffer: AVAudioPCMBuffer?
    @ObservationIgnored private var scheduledStartFrame: AVAudioFramePosition = 0
    @ObservationIgnored private var playbackSampleRate: Double = 48000
    @ObservationIgnored private var progressTimer: Timer?
    @ObservationIgnored private var playbackGeneration: UInt = 0
    @ObservationIgnored private let decodedBufferCache: NSCache<NSString, AVAudioPCMBuffer> = {
        let cache = NSCache<NSString, AVAudioPCMBuffer>()
        cache.totalCostLimit = 32 * 1024 * 1024
        cache.countLimit = 12
        return cache
    }()

    private let audioSession = AVAudioSession.sharedInstance()
    private let nowPlayingCenter = MPNowPlayingInfoCenter.default()
    private let commandCenter = MPRemoteCommandCenter.shared()

    private var playerTime: TimeInterval {
        guard let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime)
        else { return Double(scheduledStartFrame) / playbackSampleRate }
        return Double(scheduledStartFrame + playerTime.sampleTime) / playerTime.sampleRate
    }

    private static func makePCMBuffer(
        from data: Data,
        sampleRate: Double,
        channels: AVAudioChannelCount,
    ) throws -> AVAudioPCMBuffer {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channels,
            interleaved: true,
        ) else { throw PlaybackError.invalidPCM }
        let frameCount = data.count / (MemoryLayout<Float>.size * Int(channels))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))
        else { throw PlaybackError.invalidPCM }
        buffer.frameLength = AVAudioFrameCount(frameCount)
        let audioBuffer = buffer.mutableAudioBufferList.pointee.mBuffers
        guard let destination = audioBuffer.mData else { throw PlaybackError.invalidPCM }
        data.copyBytes(to: destination.assumingMemoryBound(to: UInt8.self), count: data.count)
        return buffer
    }

    private static func opusStreamFormat(from data: Data) -> (sampleRate: Double, channels: AVAudioChannelCount) {
        guard let headerRange = data.range(of: Data("OpusHead".utf8)),
              data.count >= headerRange.lowerBound + 16
        else { return (48000, 1) }
        let offset = headerRange.lowerBound
        let channels = max(1, AVAudioChannelCount(data[offset + 9]))
        let rateBytes = data[(offset + 12)..<(offset + 16)]
        let inputRate = rateBytes.enumerated().reduce(UInt32(0)) { result, item in
            result | UInt32(item.element) << UInt32(item.offset * 8)
        }
        let validRates: [UInt32] = [8000, 12000, 16000, 24000, 48000]
        let sampleRate = validRates.min { lhs, rhs in
            abs(Int64(lhs) - Int64(inputRate)) < abs(Int64(rhs) - Int64(inputRate))
        } ?? 48000
        return (Double(sampleRate), channels)
    }

    private func setCommandCenterControls() {
        commandCenter.skipBackwardCommand.preferredIntervals = [5.0]
        commandCenter.skipForwardCommand.preferredIntervals = [5.0]

        commandCenter.playCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            if !savedMediaPath.isEmpty, audioBuffer != nil, !isPlaying {
                play()
                return .success
            }
            return .commandFailed
        }

        commandCenter.pauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            if !savedMediaPath.isEmpty, audioBuffer != nil, isPlaying {
                pause()
                return .success
            }
            return .commandFailed
        }

        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            if !savedMediaPath.isEmpty, audioBuffer != nil {
                toggle()
                return .success
            }
            return .commandFailed
        }

        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self else { return .commandFailed }
            if let positionEvent = event as? MPChangePlaybackPositionCommandEvent {
                seekTo(positionEvent.positionTime)
                return .success
            }
            return .commandFailed
        }

        commandCenter.skipForwardCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            if !savedMediaPath.isEmpty, audioBuffer != nil {
                seekForward()
                return .success
            }
            return .commandFailed
        }

        commandCenter.skipBackwardCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            if !savedMediaPath.isEmpty, audioBuffer != nil {
                seekBackward()
                return .success
            }
            return .commandFailed
        }
    }

    private func toggle() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    private func pause() {
        playerNode.pause()
        isPlaying = false
        stopProgressTimer()
    }

    private func setAudioSessionPlayback() {
        do {
            try audioSession.setCategory(.playback, mode: .spokenAudio, policy: .default, options: [
                .mixWithOthers,
                .interruptSpokenAudioAndMixWithOthers,
            ])
            try audioSession.setActive(true, options: [])
        } catch {
            log("Error setting audioSessionPlayback: \(error)")
        }
    }

    private func play() {
        guard audioBuffer != nil else { return }
        setAudioSessionPlayback()
        if !playbackEngine.isRunning {
            try? playbackEngine.start()
        }
        playerNode.play()
        isPlaying = true
        startProgressTimer()
        setNowPlaying()
    }

    private func changeCurrentTime() {
        nowPlayingCenter.nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] = Double(currentTime)
    }

    private func seekTo(_ timeInterval: TimeInterval) {
        guard let audioBuffer else { return }
        let wasPlaying = isPlaying
        let targetFrame = AVAudioFramePosition(max(0, min(timeInterval, Double(duration))) * playbackSampleRate)
        schedule(buffer: audioBuffer, from: targetFrame)
        currentTime = Int32(Double(targetFrame) / playbackSampleRate)
        if wasPlaying {
            playerNode.play()
        }
    }

    private func preparePlayer(for sourcePath: String) {
        let cacheKey = sourcePath as NSString
        if let cachedBuffer = decodedBufferCache.object(forKey: cacheKey) {
            configurePlayer(with: cachedBuffer)
            play()
            return
        }
        let sourceURL = URL(filePath: sourcePath)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { () -> AVAudioPCMBuffer in
                let data = try Data(contentsOf: sourceURL, options: .mappedIfSafe)
                let streamFormat = Self.opusStreamFormat(from: data)
                let decoder = try OGGDecoder(audioData: data)
                return try Self.makePCMBuffer(
                    from: decoder.pcmData,
                    sampleRate: streamFormat.sampleRate,
                    channels: streamFormat.channels,
                )
            }
            DispatchQueue.main.async {
                guard let self, self.savedMediaPath == sourcePath else { return }
                switch result {
                case .success(let buffer):
                    self.decodedBufferCache.setObject(
                        buffer,
                        forKey: cacheKey,
                        cost: Int(buffer.frameLength) * Int(buffer.format.streamDescription.pointee.mBytesPerFrame),
                    )
                    self.configurePlayer(with: buffer)
                    self.play()
                case .failure(let error):
                    log("Failed to prepare voice message:", error)
                    self.stop()
                }
            }
        }
    }

    private func configurePlayer(with buffer: AVAudioPCMBuffer) {
        playerNode.stop()
        if playerNode.engine == nil {
            playbackEngine.attach(playerNode)
        }
        playbackEngine.disconnectNodeOutput(playerNode)
        playbackEngine.connect(playerNode, to: playbackEngine.mainMixerNode, format: buffer.format)
        audioBuffer = buffer
        playbackSampleRate = buffer.format.sampleRate
        schedule(buffer: buffer, from: 0)
        playbackEngine.prepare()
        try? playbackEngine.start()
    }

    private func schedule(buffer: AVAudioPCMBuffer, from startFrame: AVAudioFramePosition) {
        playbackGeneration &+= 1
        let generation = playbackGeneration
        playerNode.stop()
        let availableFrames = max(0, AVAudioFramePosition(buffer.frameLength) - startFrame)
        guard availableFrames > 0,
              let slice = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: AVAudioFrameCount(availableFrames))
        else { return }
        slice.frameLength = AVAudioFrameCount(availableFrames)
        let bytesPerFrame = Int(buffer.format.streamDescription.pointee.mBytesPerFrame)
        let source = buffer.audioBufferList.pointee.mBuffers
        let destination = slice.mutableAudioBufferList.pointee.mBuffers
        if let sourceBytes = source.mData, let destinationBytes = destination.mData {
            memcpy(
                destinationBytes,
                sourceBytes.advanced(by: Int(startFrame) * bytesPerFrame),
                Int(availableFrames) * bytesPerFrame,
            )
        }
        scheduledBuffer = slice
        scheduledStartFrame = startFrame
        playerNode.scheduleBuffer(slice, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.playbackGeneration == generation else { return }
                self.stop()
            }
        }
    }

    private func startProgressTimer() {
        guard progressTimer == nil else { return }
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self, isPlaying else { return }
            currentTime = Int32(playerTime)
            changeCurrentTime()
        }
    }

    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    private func setNowPlaying() {
        var info = [String: Any]()
        info[MPMediaItemPropertyTitle] = title
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = Double(currentTime)
        info[MPMediaItemPropertyPlaybackDuration] = Double(duration)
        nowPlayingCenter.nowPlayingInfo = info
    }
}
