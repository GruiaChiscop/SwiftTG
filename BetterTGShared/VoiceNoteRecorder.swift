// VoiceNoteRecorder.swift

@preconcurrency import AVFoundation
import Foundation
import SwiftOGG

/// All mutable state is only ever touched from `init`/`start()` (before the audio tap exists, so
/// nothing else can race it yet) or from within `encodingQueue.sync`/`.async` afterward - the
/// audio-render-thread tap closure and the main-thread `Timer` in `VoiceRecordingController` both
/// go through that same serial queue, which is the actual thread-safety mechanism `@unchecked`
/// asserts here.
final class VoiceNoteRecorder: @unchecked Sendable {
    // MARK: Internal

    /// Reads across `encodingQueue`, the same way `stopAndWrite`/`cancel` already do - `peakPower`
    /// is written from `updatePeak(from:count:)` on `encodingQueue` (the audio tap's callback) and
    /// was previously exposed as a plain stored property read directly by a main-thread `Timer`
    /// (`VoiceRecordingController.startTimer()`), an unsynchronized cross-thread read/write on
    /// every tick while recording.
    func currentPeakPower() -> Float {
        encodingQueue.sync { peakPower }
    }

    /// Mirrors Telegram-iOS's own voice recorder (`ManagedAudioRecorder`): the mic is already
    /// running during `warmupDuration`, but nothing captured in that window gets encoded, so
    /// whatever transient noise recording startup causes never reaches the saved file.
    func start(warmupDuration: TimeInterval) throws {
        let input = engine.inputNode
        let inputFormat = input.inputFormat(forBus: 0)
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 48000,
            channels: 1,
            interleaved: true,
        ), let converter = AVAudioConverter(from: inputFormat, to: outputFormat)
        else {
            throw RecorderError.unsupportedAudioFormat
        }

        self.converter = converter
        encoder = try OGGEncoder(
            format: outputFormat.streamDescription.pointee,
            opusRate: 48000,
            application: .voip,
        )
        compressedData = Data()
        encodedFrameCount = 0
        peakPower = -160
        isPastWarmup = false

        input.installTap(onBus: 0, bufferSize: 960, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            encodingQueue.async { [weak self] in
                self?.encode(buffer, outputFormat: outputFormat)
            }
        }
        engine.prepare()
        try engine.start()
        encodingQueue.asyncAfter(deadline: .now() + warmupDuration) { [weak self] in
            self?.isPastWarmup = true
        }
    }

    func stopAndWrite(to url: URL) throws -> TimeInterval {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        return try encodingQueue.sync {
            guard let encoder else { throw RecorderError.notRecording }
            compressedData.append(encoder.bitstream(flush: true))
            try compressedData.write(to: url, options: .atomic)
            self.encoder = nil
            converter = nil
            return Double(encodedFrameCount) / 48000
        }
    }

    func cancel() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        encodingQueue.sync {
            encoder = nil
            converter = nil
            compressedData = Data()
            encodedFrameCount = 0
        }
    }

    // MARK: Private

    private enum RecorderError: Error {
        case notRecording
        case unsupportedAudioFormat
    }

    private let engine = AVAudioEngine()
    private let encodingQueue = DispatchQueue(label: "BetterTG.VoiceNoteRecorder")
    private var converter: AVAudioConverter?
    private var encoder: OGGEncoder?
    private var compressedData = Data()
    private var encodedFrameCount: Int64 = 0
    private var peakPower: Float = -160
    private var isPastWarmup = false

    private func encode(_ inputBuffer: AVAudioPCMBuffer, outputFormat: AVAudioFormat) {
        guard isPastWarmup, let converter, let encoder else { return }
        let ratio = outputFormat.sampleRate / inputBuffer.format.sampleRate
        let capacity = AVAudioFrameCount(ceil(Double(inputBuffer.frameLength) * ratio)) + 32
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return }

        nonisolated(unsafe) var suppliedInput = false
        var conversionError: NSError?
        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, inputStatus in
            if suppliedInput {
                inputStatus.pointee = .noDataNow
                return nil
            }
            suppliedInput = true
            inputStatus.pointee = .haveData
            return inputBuffer
        }
        guard conversionError == nil, status != .error, outputBuffer.frameLength != 0 else { return }

        let audioBuffer = outputBuffer.audioBufferList.pointee.mBuffers
        guard let bytes = audioBuffer.mData else { return }
        let data = Data(bytes: bytes, count: Int(audioBuffer.mDataByteSize))
        do {
            try encoder.encode(pcm: data)
            compressedData.append(encoder.bitstream())
            encodedFrameCount += Int64(outputBuffer.frameLength)
            updatePeak(from: bytes.assumingMemoryBound(to: Int16.self), count: Int(outputBuffer.frameLength))
        } catch {
            NSLog("Voice-note streaming encoder failed: %@", String(describing: error))
        }
    }

    private func updatePeak(from samples: UnsafePointer<Int16>, count: Int) {
        guard count > 0 else { return }
        var peak: Int16 = 0
        for index in 0..<count {
            let sample = samples[index] == .min ? .max : abs(samples[index])
            peak = max(peak, sample)
        }
        let normalized = max(Float(peak) / Float(Int16.max), 0.000_000_1)
        peakPower = 20 * log10(normalized)
    }
}
