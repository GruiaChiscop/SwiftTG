// TelegramVideoNoteAssetWriterRecorder.swift

#if os(iOS)
@preconcurrency import AVFoundation
import Foundation

final class TelegramVideoNoteAssetWriterRecorder: NSObject, @unchecked Sendable {
    // MARK: Lifecycle

    override init() {
        super.init()
        videoOutput.alwaysDiscardsLateVideoFrames = false
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
        ]
        videoOutput.setSampleBufferDelegate(self, queue: recordingQueue)
        audioOutput.setSampleBufferDelegate(self, queue: recordingQueue)
    }

    deinit {
        videoOutput.setSampleBufferDelegate(nil, queue: nil)
        audioOutput.setSampleBufferDelegate(nil, queue: nil)
    }

    // MARK: Internal

    enum RecordingError: LocalizedError, Sendable {
        case alreadyRecording
        case audioSettingsUnavailable
        case noVideoFrames
        case writerFailed(String)
        case writerInitializationFailed(String)
        case videoSettingsUnavailable

        // MARK: Internal

        var errorDescription: String? {
            switch self {
            case .alreadyRecording:
                "A video message is already being recorded."
            case .audioSettingsUnavailable:
                "Audio recording settings are unavailable."
            case .noVideoFrames:
                "The camera did not produce any video frames."
            case .writerFailed(let message):
                "The video writer failed: \(message)"
            case .writerInitializationFailed(let message):
                "The video writer could not start: \(message)"
            case .videoSettingsUnavailable:
                "Video recording settings are unavailable."
            }
        }
    }

    struct SegmentResult: Sendable {
        let duration: TimeInterval
        let url: URL
    }

    let videoOutput = AVCaptureVideoDataOutput()
    let audioOutput = AVCaptureAudioDataOutput()

    func start(
        to url: URL,
        completion: @escaping @MainActor @Sendable (UUID, Result<SegmentResult, RecordingError>) async -> Void,
    ) throws -> UUID {
        try recordingQueue.sync {
            guard context == nil else { throw RecordingError.alreadyRecording }
            guard let videoSettings = videoOutput.recommendedVideoSettings(
                forVideoCodecType: .h264,
                assetWriterOutputFileType: .mp4,
            ) else { throw RecordingError.videoSettingsUnavailable }
            guard let audioSettings = audioOutput.recommendedAudioSettingsForAssetWriter(writingTo: .mp4) else {
                throw RecordingError.audioSettingsUnavailable
            }

            try? FileManager.default.removeItem(at: url)
            let writer: AVAssetWriter
            do {
                writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
            } catch {
                throw RecordingError.writerInitializationFailed(error.localizedDescription)
            }

            let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            videoInput.expectsMediaDataInRealTime = true
            let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            audioInput.expectsMediaDataInRealTime = true
            guard writer.canAdd(videoInput), writer.canAdd(audioInput) else {
                throw RecordingError.writerInitializationFailed("The encoded tracks could not be added.")
            }
            writer.add(videoInput)
            writer.add(audioInput)

            let id = UUID()
            context = SegmentContext(
                id: id,
                url: url,
                writer: writer,
                videoInput: videoInput,
                audioInput: audioInput,
                completion: completion,
            )
            return id
        }
    }

    func stop() {
        recordingQueue.async { [weak self] in
            self?.finishCurrentSegment()
        }
    }

    func cancel() {
        recordingQueue.async { [weak self] in
            guard let self, let context else { return }
            self.context = nil
            context.writer.cancelWriting()
            try? FileManager.default.removeItem(at: context.url)
        }
    }

    // MARK: Private

    private final class SegmentContext: @unchecked Sendable {
        // MARK: Lifecycle

        init(
            id: UUID,
            url: URL,
            writer: AVAssetWriter,
            videoInput: AVAssetWriterInput,
            audioInput: AVAssetWriterInput,
            completion: @escaping @MainActor @Sendable (UUID, Result<SegmentResult, RecordingError>) async -> Void,
        ) {
            self.id = id
            self.url = url
            self.writer = writer
            self.videoInput = videoInput
            self.audioInput = audioInput
            self.completion = completion
        }

        // MARK: Internal

        let id: UUID
        let url: URL
        let writer: AVAssetWriter
        let videoInput: AVAssetWriterInput
        let audioInput: AVAssetWriterInput
        let completion: @MainActor @Sendable (UUID, Result<SegmentResult, RecordingError>) async -> Void
        var firstVideoTime: CMTime?
        var lastVideoTime: CMTime?
        var pendingAudioBuffers = [CMSampleBuffer]()
        var isFinishing = false
    }

    private let recordingQueue = DispatchQueue(
        label: "com.gruiachiscop.BetterTG.video-note-writer",
        qos: .userInitiated,
    )
    private var context: SegmentContext?

    private func appendVideo(_ sampleBuffer: CMSampleBuffer, to context: SegmentContext) {
        guard !context.isFinishing else { return }
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if context.writer.status == .unknown {
            guard context.writer.startWriting() else {
                fail(context, message: context.writer.error?.localizedDescription ?? "Unknown writer error")
                return
            }
            context.writer.startSession(atSourceTime: presentationTime)
            context.firstVideoTime = presentationTime
            appendPendingAudio(to: context)
        }

        guard context.writer.status == .writing else {
            fail(context, message: context.writer.error?.localizedDescription ?? "The writer stopped unexpectedly")
            return
        }
        guard context.videoInput.isReadyForMoreMediaData else { return }
        if context.videoInput.append(sampleBuffer) {
            context.lastVideoTime = presentationTime
        } else {
            fail(context, message: context.writer.error?.localizedDescription ?? "A video frame could not be written")
        }
    }

    private func appendAudio(_ sampleBuffer: CMSampleBuffer, to context: SegmentContext) {
        guard !context.isFinishing else { return }
        guard let firstVideoTime = context.firstVideoTime else {
            if context.pendingAudioBuffers.count < 100 {
                context.pendingAudioBuffers.append(sampleBuffer)
            }
            return
        }
        guard CMSampleBufferGetPresentationTimeStamp(sampleBuffer) >= firstVideoTime,
              context.writer.status == .writing,
              context.audioInput.isReadyForMoreMediaData
        else { return }
        if !context.audioInput.append(sampleBuffer) {
            fail(context, message: context.writer.error?.localizedDescription ?? "An audio sample could not be written")
        }
    }

    private func appendPendingAudio(to context: SegmentContext) {
        let pendingBuffers = context.pendingAudioBuffers
        context.pendingAudioBuffers.removeAll(keepingCapacity: true)
        for sampleBuffer in pendingBuffers {
            appendAudio(sampleBuffer, to: context)
        }
    }

    private func finishCurrentSegment() {
        guard let context, !context.isFinishing else { return }
        context.isFinishing = true
        context.pendingAudioBuffers.removeAll()

        guard context.writer.status == .writing,
              let firstVideoTime = context.firstVideoTime,
              let lastVideoTime = context.lastVideoTime
        else {
            context.writer.cancelWriting()
            complete(context, with: .failure(.noVideoFrames))
            return
        }

        context.videoInput.markAsFinished()
        context.audioInput.markAsFinished()
        let duration = max(0, (lastVideoTime - firstVideoTime).seconds)
        context.writer.finishWriting { [weak self, context] in
            self?.recordingQueue.async { [weak self, context] in
                guard let self else { return }
                if context.writer.status == .completed {
                    complete(context, with: .success(.init(duration: duration, url: context.url)))
                } else {
                    complete(
                        context,
                        with: .failure(.writerFailed(
                            context.writer.error?.localizedDescription ?? "The MP4 file could not be finalized",
                        )),
                    )
                }
            }
        }
    }

    private func fail(_ context: SegmentContext, message: String) {
        context.writer.cancelWriting()
        complete(context, with: .failure(.writerFailed(message)))
    }

    private func complete(_ context: SegmentContext, with result: Result<SegmentResult, RecordingError>) {
        guard self.context === context else { return }
        self.context = nil
        let id = context.id
        let completion = context.completion
        Task { @MainActor in
            await completion(id, result)
        }
    }
}

extension TelegramVideoNoteAssetWriterRecorder: AVCaptureVideoDataOutputSampleBufferDelegate,
    AVCaptureAudioDataOutputSampleBufferDelegate
{
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from _: AVCaptureConnection,
    ) {
        guard CMSampleBufferDataIsReady(sampleBuffer), let context else { return }
        if output === videoOutput {
            appendVideo(sampleBuffer, to: context)
        } else if output === audioOutput {
            appendAudio(sampleBuffer, to: context)
        }
    }
}
#endif
