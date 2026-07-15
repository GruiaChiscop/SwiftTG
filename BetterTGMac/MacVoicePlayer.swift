import AVFoundation
import Observation
import SwiftOGG

private enum MacVoicePlaybackError: Error { case invalidPCM }

@MainActor @Observable final class MacVoicePlayer {
    static let shared = MacVoicePlayer()

    var currentFileId: Int?
    var currentTime = 0
    var isPlaying = false

    func toggle(fileId: Int, path: String, duration: Int) {
        self.duration = duration
        if currentFileId != fileId {
            stop()
            currentFileId = fileId
            preparePlayer(path: path, fileId: fileId)
        } else if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func seekBackward() {
        seek(to: max(0, playerTime - 5))
    }

    func seekForward() {
        seek(to: min(Double(duration), playerTime + 5))
    }

    private init() {}

    private func play() {
        guard audioBuffer != nil else { return }
        if !engine.isRunning { try? engine.start() }
        player.play()
        isPlaying = true
        startTimer()
    }

    private func pause() {
        player.pause()
        isPlaying = false
        stopTimer()
    }

    func stop() {
        generation &+= 1
        player.stop()
        isPlaying = false
        currentTime = 0
        currentFileId = nil
        audioBuffer = nil
        stopTimer()
    }

    private func seek(to seconds: TimeInterval) {
        guard let audioBuffer else { return }
        let wasPlaying = isPlaying
        let frame = AVAudioFramePosition(max(0, min(seconds, Double(duration))) * sampleRate)
        schedule(buffer: audioBuffer, from: frame)
        currentTime = Int(Double(frame) / sampleRate)
        if wasPlaying { player.play() }
    }

    private var playerTime: TimeInterval {
        guard let nodeTime = player.lastRenderTime,
              let time = player.playerTime(forNodeTime: nodeTime)
        else { return Double(scheduledStartFrame) / sampleRate }
        return Double(scheduledStartFrame + time.sampleTime) / time.sampleRate
    }

    private func preparePlayer(path: String, fileId: Int) {
        let sourceURL = URL(filePath: path)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { () -> AVAudioPCMBuffer in
                let data = try Data(contentsOf: sourceURL, options: .mappedIfSafe)
                let format = Self.opusStreamFormat(from: data)
                let decoder = try OGGDecoder(audioData: data)
                return try Self.makePCMBuffer(
                    from: decoder.pcmData,
                    sampleRate: format.sampleRate,
                    channels: format.channels,
                )
            }
            DispatchQueue.main.async {
                guard let self, self.currentFileId == fileId else { return }
                guard case .success(let buffer) = result else {
                    self.stop()
                    return
                }
                self.configure(with: buffer)
                self.play()
            }
        }
    }

    private func configure(with buffer: AVAudioPCMBuffer) {
        player.stop()
        if player.engine == nil { engine.attach(player) }
        engine.disconnectNodeOutput(player)
        engine.connect(player, to: engine.mainMixerNode, format: buffer.format)
        audioBuffer = buffer
        sampleRate = buffer.format.sampleRate
        schedule(buffer: buffer, from: 0)
        engine.prepare()
        try? engine.start()
    }

    private func schedule(buffer: AVAudioPCMBuffer, from startFrame: AVAudioFramePosition) {
        generation &+= 1
        let scheduledGeneration = generation
        player.stop()
        let availableFrames = max(0, AVAudioFramePosition(buffer.frameLength) - startFrame)
        guard availableFrames > 0,
              let slice = AVAudioPCMBuffer(
                  pcmFormat: buffer.format,
                  frameCapacity: AVAudioFrameCount(availableFrames),
              )
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
        scheduledStartFrame = startFrame
        player.scheduleBuffer(slice, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.generation == scheduledGeneration else { return }
                self.stop()
            }
        }
    }

    private func startTimer() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isPlaying else { return }
                self.currentTime = Int(self.playerTime)
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    nonisolated private static func makePCMBuffer(
        from data: Data,
        sampleRate: Double,
        channels: AVAudioChannelCount,
    ) throws -> AVAudioPCMBuffer {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channels,
            interleaved: true,
        ) else { throw MacVoicePlaybackError.invalidPCM }
        let frameCount = data.count / (MemoryLayout<Float>.size * Int(channels))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))
        else { throw MacVoicePlaybackError.invalidPCM }
        buffer.frameLength = AVAudioFrameCount(frameCount)
        guard let destination = buffer.mutableAudioBufferList.pointee.mBuffers.mData else {
            throw MacVoicePlaybackError.invalidPCM
        }
        data.copyBytes(to: destination.assumingMemoryBound(to: UInt8.self), count: data.count)
        return buffer
    }

    nonisolated private static func opusStreamFormat(from data: Data) -> (sampleRate: Double, channels: AVAudioChannelCount) {
        guard let headerRange = data.range(of: Data("OpusHead".utf8)),
              data.count >= headerRange.lowerBound + 16
        else { return (48_000, 1) }
        let offset = headerRange.lowerBound
        let channels = max(1, AVAudioChannelCount(data[offset + 9]))
        let rateBytes = data[(offset + 12) ..< (offset + 16)]
        let inputRate = rateBytes.enumerated().reduce(UInt32(0)) { result, item in
            result | UInt32(item.element) << UInt32(item.offset * 8)
        }
        let validRates: [UInt32] = [8_000, 12_000, 16_000, 24_000, 48_000]
        let rate = validRates.min {
            abs(Int64($0) - Int64(inputRate)) < abs(Int64($1) - Int64(inputRate))
        } ?? 48_000
        return (Double(rate), channels)
    }

    @ObservationIgnored private var audioBuffer: AVAudioPCMBuffer?
    @ObservationIgnored private var duration = 0
    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var generation: UInt = 0
    @ObservationIgnored private let player = AVAudioPlayerNode()
    @ObservationIgnored private var sampleRate = 48_000.0
    @ObservationIgnored private var scheduledStartFrame: AVAudioFramePosition = 0
    @ObservationIgnored private var timer: Timer?
}
