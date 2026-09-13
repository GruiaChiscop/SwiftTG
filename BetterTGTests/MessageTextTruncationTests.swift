// MessageTextTruncationTests.swift

@testable import BetterTG
import Foundation
import SwiftUI
import Testing

struct MessageTextTruncationTests {
    @Test func `short text is not truncated`() {
        #expect(truncatedMessageDisplayText(AttributedString("Hello there")) == nil)
    }

    @Test func `text exactly at the character limit is not truncated`() {
        let text = AttributedString(String(repeating: "a", count: 500))
        #expect(truncatedMessageDisplayText(text) == nil)
    }

    @Test func `text past the character limit is truncated with an ellipsis`() {
        let text = AttributedString(String(repeating: "a", count: 501))
        let result = truncatedMessageDisplayText(text)

        #expect(result != nil)
        #expect(String(result!.characters).hasSuffix("…"))
        #expect(String(result!.characters).count == 501) // 500 kept chars + the ellipsis
    }

    @Test func `text past the line limit is truncated even if short`() {
        let text = AttributedString(String(repeating: "hi\n", count: 20))
        let result = truncatedMessageDisplayText(text)

        #expect(result != nil)
        #expect(String(result!.characters).components(separatedBy: "\n").count - 1 == 14)
    }

    @Test func `text exactly at the line limit is not truncated`() {
        let text = AttributedString(String(repeating: "hi\n", count: 13) + "hi")
        #expect(truncatedMessageDisplayText(text) == nil)
    }

    @Test func `truncation preserves formatting attributes on the kept prefix`() {
        var text = AttributedString(String(repeating: "a", count: 600))
        text.font = .body.bold()

        let result = truncatedMessageDisplayText(text)

        #expect(result != nil)
        let firstRun = result!.runs.first
        #expect(firstRun?.font == .body.bold())
    }
}
