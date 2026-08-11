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
}
