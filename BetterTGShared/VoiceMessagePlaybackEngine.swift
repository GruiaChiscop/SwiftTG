// VoiceMessagePlaybackEngine.swift

@preconcurrency import AVFoundation
import Observation
import SwiftOGG

/// Shared Opus-in-OGG decode + AVAudioEngine playback core for voice messages, used by both the
/// iOS (`Media`) and macOS (`MacVoicePlayer`) wrappers, which add their own platform-specific
/// concerns (audio session setup, Now Playing/remote-command integration on iOS; nothing extra on
/// macOS) around this.
@MainActor
@Observable final class VoiceMessagePlaybackEngine {
    // MARK: Lifecycle

    init() {}

    // MARK: Internal

    private(set) var isPlaying = false
    private(set) var currentTime = 0
    private(set) var currentPath: String?
    var duration = 0

    /// Diagnostic hook; no-op by default. iOS wires this to `voicePlaybackTrace`.
    var trace: (String) -> Void = { _ in }
    /// Called right before playback starts; returning `false` aborts `play()` before the engine
    /// starts. iOS wires this to its `AVAudioSession` playback category setup; macOS doesn't need
    /// one, so it keeps the default.
    var onWillPlay: () -> Bool = { true }
    /// Called each time the progress timer ticks while playing.
    var onTick: (() -> Void)?
    /// Called right after playback successfully starts.
    var onPlayStarted: (() -> Void)?
    /// Called whenever playback stops, including auto-stop at the end of the buffer.
    var onStopped: (() -> Void)?

    /// Whether a decoded buffer is ready to play (as opposed to still downloading/decoding).
    var isReady: Bool { audioBuffer != nil }

    func toggle(path: String, duration: Int) {
        trace("toggle newPath=\(currentPath != path) duration=\(duration)")
        self.duration = duration
        if currentPath != path {
            stop()
            currentPath = path
            preparePlayer(for: path)
        } else if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func play() {
        guard audioBuffer != nil else {
            trace("play aborted: no PCM buffer")
            return
        }
        guard onWillPlay() else { return }
        do {
            if !engine.isRunning {
                try engine.start()
            }
        } catch {
            trace("engine start failed: \(error.localizedDescription)")
            isPlaying = false
            return
        }
        playerNode.play()
        isPlaying = true
        trace("player started engineRunning=\(engine.isRunning) nodePlaying=\(playerNode.isPlaying)")
        startProgressTimer()
        onPlayStarted?()
    }

    func pause() {
        playerNode.pause()
        isPlaying = false
        stopProgressTimer()
    }

    func stop() {
        generation &+= 1
        isPlaying = false
        currentTime = 0
        currentPath = nil
        stopProgressTimer()
        playerNode.stop()
        engine.stop()
        audioBuffer = nil
        onStopped?()
    }

    func seek(to seconds: TimeInterval) {
        guard let audioBuffer else { return }
        let wasPlaying = isPlaying
        let targetFrame = AVAudioFramePosition(max(0, min(seconds, Double(duration))) * sampleRate)
        schedule(buffer: audioBuffer, from: targetFrame)
        currentTime = Int(Double(targetFrame) / sampleRate)
        if wasPlaying {
            playerNode.play()
        }
    }

    func seekForward() {
        seek(to: playerTime + 5)
    }

    func seekBackward() {
        seek(to: max(0, playerTime - 5))
    }

    // MARK: Private

    private enum PlaybackError: Error { case invalidPCM }

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private let playerNode = AVAudioPlayerNode()
    @ObservationIgnored private var audioBuffer: AVAudioPCMBuffer?
    @ObservationIgnored private var sampleRate: Double = 48000
    @ObservationIgnored private var scheduledStartFrame: AVAudioFramePosition = 0
    @ObservationIgnored private var progressTimer: Timer?
    @ObservationIgnored private var generation: UInt = 0
    @ObservationIgnored private let decodedBufferCache: NSCache<NSString, AVAudioPCMBuffer> = {
        let cache = NSCache<NSString, AVAudioPCMBuffer>()
        cache.totalCostLimit = 32 * 1024 * 1024
        cache.countLimit = 12
        return cache
    }()

    private var playerTime: TimeInterval {
        guard let nodeTime = playerNode.lastRenderTime,
              let time = playerNode.playerTime(forNodeTime: nodeTime)
        else { return Double(scheduledStartFrame) / sampleRate }
        return Double(scheduledStartFrame + time.sampleTime) / time.sampleRate
    }

    private nonisolated static func makePCMBuffer(
        from data: Data,
        sampleRate: Double,
        channels: AVAudioChannelCount,
    ) throws -> AVAudioPCMBuffer {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channels,
            interleaved: false,
        ) else { throw PlaybackError.invalidPCM }
        let frameCount = data.count / (MemoryLayout<Float>.size * Int(channels))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))
        else { throw PlaybackError.invalidPCM }
        buffer.frameLength = AVAudioFrameCount(frameCount)
        guard let destinationChannels = buffer.floatChannelData else { throw PlaybackError.invalidPCM }
        data.withUnsafeBytes { rawBuffer in
            let source = rawBuffer.bindMemory(to: Float.self)
            for frame in 0..<frameCount {
                for channel in 0..<Int(channels) {
                    destinationChannels[channel][frame] = source[frame * Int(channels) + channel]
                }
            }
        }
        return buffer
    }

    private nonisolated static func opusStreamFormat(from data: Data)
    -> (sampleRate: Double, channels: AVAudioChannelCount) {
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

    private func preparePlayer(for sourcePath: String) {
        let cacheKey = sourcePath as NSString
        if let cachedBuffer = decodedBufferCache.object(forKey: cacheKey) {
            configure(with: cachedBuffer)
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
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.currentPath == sourcePath else { return }
                    switch result {
                    case .success(let buffer) where buffer.frameLength > 0:
                        self.decodedBufferCache.setObject(
                            buffer,
                            forKey: sourcePath as NSString,
                            cost: Int(buffer.frameLength) * Int(buffer.format.streamDescription.pointee.mBytesPerFrame),
                        )
                        self.configure(with: buffer)
                        self.play()
                    case .success:
                        // configure/schedule silently no-op on an empty buffer, which would
                        // otherwise leave play() reporting isPlaying = true with nothing
                        // actually scheduled - audible as complete silence with no error.
                        self.trace("decode produced empty buffer, refusing to play")
                        self.stop()
                    case .failure(let error):
                        self.trace("decode failed: \(error.localizedDescription)")
                        self.stop()
                    }
                }
            }
        }
    }

    private func configure(with buffer: AVAudioPCMBuffer) {
        trace("configure frames=\(buffer.frameLength) format=\(buffer.format)")
        playerNode.stop()
        if playerNode.engine == nil {
            engine.attach(playerNode)
        }
        engine.disconnectNodeOutput(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: buffer.format)
        audioBuffer = buffer
        sampleRate = buffer.format.sampleRate
        schedule(buffer: buffer, from: 0)
        engine.prepare()
    }

    private func schedule(buffer: AVAudioPCMBuffer, from startFrame: AVAudioFramePosition) {
        generation &+= 1
        let scheduledGeneration = generation
        playerNode.stop()
        let availableFrames = max(0, AVAudioFramePosition(buffer.frameLength) - startFrame)
        guard availableFrames > 0,
              let slice = AVAudioPCMBuffer(
                  pcmFormat: buffer.format,
                  frameCapacity: AVAudioFrameCount(availableFrames),
              )
        else { return }
        slice.frameLength = AVAudioFrameCount(availableFrames)
        guard let sourceChannels = buffer.floatChannelData,
              let destinationChannels = slice.floatChannelData
        else { return }
        for channel in 0..<Int(buffer.format.channelCount) {
            memcpy(
                destinationChannels[channel],
                sourceChannels[channel].advanced(by: Int(startFrame)),
                Int(availableFrames) * MemoryLayout<Float>.size,
            )
        }
        scheduledStartFrame = startFrame
        playerNode.scheduleBuffer(slice, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.generation == scheduledGeneration else { return }
                    self.stop()
                }
            }
        }
    }

    private func startProgressTimer() {
        guard progressTimer == nil else { return }
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, isPlaying else { return }
                currentTime = Int(playerTime)
                onTick?()
            }
        }
    }

    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }
}
