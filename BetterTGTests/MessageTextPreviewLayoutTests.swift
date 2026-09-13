// MessageTextPreviewLayoutTests.swift

@testable import BetterTG
import SwiftUI
import Testing
import UIKit

@MainActor struct MessageTextPreviewLayoutTests {
    // MARK: Internal

    @Test func `short message keeps its natural height`() {
        let size = measure("Hello", shortened: false, width: 280, budget: 320)
        #expect(size.height > 0)
        #expect(size.height < 80)
    }

    @Test func `wrapped text fits even below the character limit`() {
        let text = String(repeating: "Wide words wrap. ", count: 25)
        #expect(text.count < 500)
        for width: CGFloat in [180, 280] {
            for budget: CGFloat in [120, 220, 320] {
                let size = measure(text, shortened: false, width: width, budget: budget)
                #expect(size.height <= budget + 1)
                #expect(size.height > 0)
            }
        }
    }

    @Test func `shortened preview fits with large type and metadata`() {
        let size = measure(
            String(repeating: "Long message ", count: 40),
            shortened: true, width: 230, budget: 260, typeSize: .accessibility3,
        )
        #expect(size.height <= 261)
        #expect(size.height > 0)
    }

    @Test func `pinned banner uses content height instead of available height`() {
        let banner = StablePinnedMessageBanner(summary: "A pinned message", openMessage: {}, showAllMessages: {})
        let host = UIHostingController(rootView: banner)
        let size = host.sizeThatFits(in: CGSize(width: 390, height: 800))
        #expect(size.height >= 44)
        #expect(size.height < 120)
    }

    // MARK: Private

    private func measure(
        _ text: String,
        shortened: Bool,
        width: CGFloat,
        budget: CGFloat,
        typeSize: DynamicTypeSize = .large,
    ) -> CGSize {
        let preview = MessageTextPreview(
            text: AttributedString(text),
            isShortened: shortened,
            trailingText: AttributedString(" 23:35"),
            maximumHeight: budget,
            showFullText: {},
        )
        .dynamicTypeSize(typeSize)
        .fixedSize(horizontal: false, vertical: true)
        let host = UIHostingController(rootView: preview)
        return host.sizeThatFits(in: CGSize(width: width, height: 10000))
    }
}
