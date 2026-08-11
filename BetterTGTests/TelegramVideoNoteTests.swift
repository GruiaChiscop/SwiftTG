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

    @Test func `raw capture uses QuickTime while the sent artifact uses MP4`() {
        let staging = TelegramOutgoingFileStaging(
            directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString),
        )

        #expect(staging.videoNoteFileURL(isRawRecording: true).pathExtension == "mov")
        #expect(staging.videoNoteAssetWriterFileURL().pathExtension == "mp4")
        #expect(staging.videoNoteFileURL().pathExtension == "mp4")
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
}
