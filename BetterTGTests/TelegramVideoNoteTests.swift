// TelegramVideoNoteTests.swift

@testable import BetterTG
import CoreGraphics
import Foundation
import TDLibKit
import Testing

struct TelegramVideoNoteTests {
    @Test func `outgoing video note clamps Telegram limits`() {
        let content = TelegramVideoNoteSending.content(
            url: URL(filePath: "/tmp/video.mp4"),
            duration: 90,
            length: 900,
        )
        guard case .inputMessageVideoNote(let input) = content else {
            Issue.record("Expected a video note")
            return
        }

        #expect(input.videoNote.duration == 60)
        #expect(input.videoNote.length == 640)
        #expect(input.selfDestructType == nil)
    }

    @Test func `view once video note uses immediate self destruction`() {
        let content = TelegramVideoNoteSending.content(
            url: URL(filePath: "/tmp/video.mp4"),
            duration: 12,
            isViewOnce: true,
        )
        guard case .inputMessageVideoNote(let input) = content else {
            Issue.record("Expected a video note")
            return
        }

        #expect(input.selfDestructType == MessageSelfDestructType.messageSelfDestructTypeImmediately)
    }

    @Test func `video note includes its generated thumbnail`() {
        let thumbnailURL = URL(filePath: "/tmp/video-thumbnail.jpeg")
        let content = TelegramVideoNoteSending.content(
            url: URL(filePath: "/tmp/video.mp4"),
            thumbnail: TelegramVideoNoteThumbnail(url: thumbnailURL, width: 320, height: 300),
            duration: 12,
        )
        guard case .inputMessageVideoNote(let input) = content,
              let thumbnail = input.videoNote.thumbnail,
              case .inputFileLocal(let file) = thumbnail.thumbnail
        else {
            Issue.record("Expected a local video-note thumbnail")
            return
        }

        #expect(thumbnail.width == 320)
        #expect(thumbnail.height == 300)
        #expect(file.path == thumbnailURL.path())
    }

    @Test func `video note can reuse a preliminary upload`() {
        let content = TelegramVideoNoteSending.content(
            url: URL(filePath: "/tmp/video.mp4"),
            preliminaryUploadFileId: 42,
            duration: 12,
        )
        guard case .inputMessageVideoNote(let input) = content,
              case .inputFileId(let file) = input.videoNote.videoNote
        else {
            Issue.record("Expected a preliminary-upload file identifier")
            return
        }

        #expect(file.id == 42)
    }

    @Test func `recorded file is reused only without recording adjustments`() {
        #expect(TelegramVideoNoteRecordedFileReusePolicy.canReuse(
            segmentCount: 1,
            trimRange: 0..<12,
            duration: 12,
        ))
        #expect(!TelegramVideoNoteRecordedFileReusePolicy.canReuse(
            segmentCount: 2,
            trimRange: 0..<12,
            duration: 12,
        ))
        #expect(!TelegramVideoNoteRecordedFileReusePolicy.canReuse(
            segmentCount: 1,
            trimRange: 1..<12,
            duration: 12,
        ))
    }

    @Test func `message effect is forwarded through send options`() {
        let effectId: TdInt64 = 123
        let options = TelegramMessageSending.sendOptions(effectId: effectId)

        #expect(options?.effectId == effectId)
    }

    @Test func `schedule recurrence exposes only TDLib production intervals`() {
        #expect(TelegramMessageRepeatPeriod.allCases.map(\.rawValue) == [
            0,
            86400,
            604_800,
            1_209_600,
            2_592_000,
            7_862_400,
            15_724_800,
            31_536_000,
        ])
    }

    @Test func `recorded video is cropped to its centered square`() {
        #expect(TelegramVideoNoteTranscoder.centeredSquareCrop(in: CGRect(x: 0, y: 0, width: 1920, height: 1080)) ==
            CGRect(x: 420, y: 0, width: 1080, height: 1080))
        #expect(TelegramVideoNoteTranscoder.centeredSquareCrop(in: CGRect(x: 0, y: 0, width: 720, height: 1280)) ==
            CGRect(x: 0, y: 280, width: 720, height: 720))
    }

    @Test func `paused video note segments share the sixty second limit`() {
        #expect(TelegramVideoNoteRecordingLimits.totalDuration(completed: 22, current: 13) == 35)
        #expect(TelegramVideoNoteRecordingLimits.remainingDuration(after: 35) == 25)
        #expect(TelegramVideoNoteRecordingLimits.totalDuration(completed: 58, current: 5) == 60)
        #expect(TelegramVideoNoteRecordingLimits.remainingDuration(after: 63) == 0)
    }

    @Test func `camera zoom respects one times and device limits`() {
        #expect(TelegramVideoNoteCameraControls.clampedZoom(0.5, maximumDeviceZoom: 4) == 1)
        #expect(TelegramVideoNoteCameraControls.clampedZoom(2.5, maximumDeviceZoom: 4) == 2.5)
        #expect(TelegramVideoNoteCameraControls.clampedZoom(8, maximumDeviceZoom: 4) == 4)
        #expect(TelegramVideoNoteCameraControls.clampedZoom(8, maximumDeviceZoom: 12) == 5)
    }

    @Test func `front camera flash uses the screen only while enabled`() {
        #expect(TelegramVideoNoteCameraControls.usesScreenFlash(position: .front, isFlashEnabled: true))
        #expect(!TelegramVideoNoteCameraControls.usesScreenFlash(position: .front, isFlashEnabled: false))
        #expect(!TelegramVideoNoteCameraControls.usesScreenFlash(position: .back, isFlashEnabled: true))
    }

    @Test func `dual camera is gated by support and capture costs`() {
        #expect(TelegramVideoNoteCameraControls.shouldUseConcurrentCameras(
            isSupported: true,
            hardwareCost: 0.8,
            systemPressureCost: 0.7,
        ))
        #expect(!TelegramVideoNoteCameraControls.shouldUseConcurrentCameras(
            isSupported: false,
            hardwareCost: 0.5,
            systemPressureCost: 0.5,
        ))
        #expect(!TelegramVideoNoteCameraControls.shouldUseConcurrentCameras(
            isSupported: true,
            hardwareCost: 1.1,
            systemPressureCost: 0.5,
        ))
    }

    @Test func `video message trim range remains ordered and in bounds`() {
        #expect(TelegramVideoNoteEditing.normalizedTrimRange(start: -2, end: 20, duration: 10) == 0..<10)
        #expect(TelegramVideoNoteEditing.normalizedTrimRange(start: 0, end: 0, duration: 10) == 0..<10)
        #expect(TelegramVideoNoteEditing.normalizedTrimRange(start: 8, end: 7, duration: 10) == 8..<9)
        #expect(TelegramVideoNoteEditing.normalizedTrimRange(start: 12, end: 20, duration: 10) == 9..<10)
        #expect(TelegramVideoNoteEditing.normalizedTrimRange(start: 0, end: 1, duration: 0) == 0..<0)
        #expect(!TelegramVideoNoteEditing.isSendableDuration(0.999))
        #expect(TelegramVideoNoteEditing.isSendableDuration(1))
    }

    @Test func `raw capture uses QuickTime while the sent artifact uses MP4`() {
        let staging = TelegramOutgoingFileStaging(
            directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString),
        )

        #expect(staging.videoNoteFileURL(isRawRecording: true).pathExtension == "mov")
        #expect(staging.videoNoteAssetWriterFileURL().pathExtension == "mp4")
        #expect(staging.videoNoteFileURL().pathExtension == "mp4")
        #expect(staging.videoNoteThumbnailFileURL().pathExtension == "jpeg")
    }

    @Test func `sent video note remains available to its live message`() throws {
        let directory = FileManager.default
            .temporaryDirectory
            .appending(path: "BetterTGVideoNoteStagingTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let staging = TelegramOutgoingFileStaging(directory: directory)
        let fileURL = staging.videoNoteFileURL()
        try Data([1, 2, 3]).write(to: fileURL)

        staging.register(
            fileURL: fileURL,
            chatId: 10,
            temporaryMessageId: -20,
            successfulSendCleanup: .retainUntilStale,
        )
        staging.messageSendSucceeded(chatId: 10, oldMessageId: -20)

        #expect(FileManager.default.fileExists(atPath: fileURL.path()))
    }

    @Test func `video and thumbnail share one staging lifecycle`() throws {
        let directory = FileManager.default
            .temporaryDirectory
            .appending(path: "BetterTGVideoNoteStagingTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let staging = TelegramOutgoingFileStaging(directory: directory)
        let videoURL = staging.videoNoteFileURL()
        let thumbnailURL = staging.videoNoteThumbnailFileURL()
        try Data([1, 2, 3]).write(to: videoURL)
        try Data([4, 5, 6]).write(to: thumbnailURL)

        staging.register(
            fileURLs: [videoURL, thumbnailURL],
            chatId: 10,
            temporaryMessageId: -20,
        )
        staging.messageSendSucceeded(chatId: 10, oldMessageId: -20)

        #expect(!FileManager.default.fileExists(atPath: videoURL.path()))
        #expect(!FileManager.default.fileExists(atPath: thumbnailURL.path()))
    }
}
