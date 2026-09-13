// ChatHistoryUITableViewTests.swift

@testable import BetterTG
import CoreGraphics
import Testing

@MainActor struct ChatHistoryUITableViewTests {
    @Test func `content size changes are coalesced after UIKit layout`() async {
        let tableView = ChatHistoryUITableView(frame: .zero, style: .plain)
        var notificationCount = 0
        tableView.onContentSizeChange = { notificationCount += 1 }

        tableView.contentSize = CGSize(width: 320, height: 400)
        tableView.contentSize = CGSize(width: 320, height: 800)
        await Task.yield()
        await Task.yield()

        #expect(notificationCount == 1)
    }

    @Test func `assigning the same content size does not notify`() async {
        let tableView = ChatHistoryUITableView(frame: .zero, style: .plain)
        tableView.contentSize = CGSize(width: 320, height: 400)
        await Task.yield()
        await Task.yield()

        var notificationCount = 0
        tableView.onContentSizeChange = { notificationCount += 1 }
        tableView.contentSize = tableView.contentSize
        await Task.yield()
        await Task.yield()

        #expect(notificationCount == 0)
    }
}
