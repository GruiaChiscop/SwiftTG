// ChatHistoryTableMetricsTests.swift

@testable import BetterTG
import Testing

struct ChatHistoryTableMetricsTests {
    @Test func `short history is inset to the bottom of the viewport`() {
        #expect(ChatHistoryTableMetrics.topContentInset(contentHeight: 300, viewportHeight: 700) == 400)
        #expect(ChatHistoryTableMetrics.topContentInset(contentHeight: 900, viewportHeight: 700) == 0)
    }

    @Test func `bottom aligned short history is at bottom without a scroll button`() {
        let state = ChatHistoryTableMetrics.scrollState(
            contentHeight: 300,
            viewportHeight: 700,
            topInset: 400,
            bottomInset: 0,
            contentOffsetY: -400,
        )

        #expect(state.isAtBottom)
        #expect(!state.shouldShowBottomButton)
    }

    @Test func `scroll button appears only after moving more than one page from bottom`() {
        let onePageAway = ChatHistoryTableMetrics.scrollState(
            contentHeight: 2000,
            viewportHeight: 600,
            topInset: 0,
            bottomInset: 0,
            contentOffsetY: 800,
        )
        let overOnePageAway = ChatHistoryTableMetrics.scrollState(
            contentHeight: 2000,
            viewportHeight: 600,
            topInset: 0,
            bottomInset: 0,
            contentOffsetY: 799,
        )

        #expect(!onePageAway.shouldShowBottomButton)
        #expect(overOnePageAway.shouldShowBottomButton)
    }

    @Test func `prepending rows before the visible message requires anchor restoration`() {
        #expect(ChatHistoryTableMetrics.itemsBeforeAnchorChanged(
            20,
            oldIDs: [10, 20, 30],
            newIDs: [1, 2, 10, 20, 30],
        ))
    }

    @Test func `deleting rows before the visible message requires anchor restoration`() {
        #expect(ChatHistoryTableMetrics.itemsBeforeAnchorChanged(
            20,
            oldIDs: [1, 2, 10, 20, 30],
            newIDs: [10, 20, 30],
        ))
    }

    @Test func `replacing a day marker before the visible message requires anchor restoration`() {
        #expect(ChatHistoryTableMetrics.itemsBeforeAnchorChanged(
            "message-20",
            oldIDs: ["day-10", "message-10", "message-20"],
            newIDs: ["day-1", "message-1", "message-10", "message-20"],
        ))
    }

    @Test func `appending or retaining the same prefix does not restore the visible anchor`() {
        #expect(!ChatHistoryTableMetrics.itemsBeforeAnchorChanged(
            20,
            oldIDs: [10, 20, 30],
            newIDs: [10, 20, 30, 40],
        ))
        #expect(!ChatHistoryTableMetrics.itemsBeforeAnchorChanged(
            20,
            oldIDs: [10, 20, 30],
            newIDs: [10, 20, 30],
        ))
    }

    @Test func `missing anchor cannot request restoration`() {
        #expect(!ChatHistoryTableMetrics.itemsBeforeAnchorChanged(
            99,
            oldIDs: [10, 20, 30],
            newIDs: [10, 20, 30],
        ))
    }

    @Test func `topContentInset fills the whole viewport when there is no content`() {
        #expect(ChatHistoryTableMetrics.topContentInset(contentHeight: 0, viewportHeight: 500) == 500)
    }

    @Test func `content that exactly fills the viewport is always at the bottom`() {
        let state = ChatHistoryTableMetrics.scrollState(
            contentHeight: 600,
            viewportHeight: 600,
            topInset: 0,
            bottomInset: 0,
            contentOffsetY: 0,
        )

        #expect(state.isAtBottom)
        #expect(!state.shouldShowBottomButton)
    }

    @Test func `anchor removed from the new items does not request restoration`() {
        #expect(!ChatHistoryTableMetrics.itemsBeforeAnchorChanged(
            20,
            oldIDs: [10, 20, 30],
            newIDs: [10, 30],
        ))
    }

    @Test func `anchor missing from the old items does not request restoration`() {
        #expect(!ChatHistoryTableMetrics.itemsBeforeAnchorChanged(
            20,
            oldIDs: [10, 30],
            newIDs: [10, 20, 30],
        ))
    }

    @Test func `bottom tolerance ignores bounce but excludes twenty points`() {
        let bounce = ChatHistoryTableMetrics.scrollState(
            contentHeight: 1000,
            viewportHeight: 600,
            topInset: 0,
            bottomInset: 0,
            contentOffsetY: 410,
        )
        let boundary = ChatHistoryTableMetrics.scrollState(
            contentHeight: 1000,
            viewportHeight: 600,
            topInset: 0,
            bottomInset: 0,
            contentOffsetY: 380,
        )

        #expect(bounce.isAtBottom)
        #expect(!boundary.isAtBottom)
    }
}
