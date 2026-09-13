// ChatHistoryTableViewControllerTests.swift

@testable import BetterTG
import SwiftUI
import Testing
import UIKit

@MainActor struct ChatHistoryTableViewControllerTests {
    @Test func `updating the controller renders one row per history item`() async {
        let controller = makeController()
        let chatVM = makeChatVM()
        let messages = makeMessages(count: 3, chatVM: chatVM)

        controller.update(makeConfiguration(chatVM: chatVM, messages: messages))
        await waitUntilRowCount(controller, equals: 4) // 1 day header + 3 messages

        #expect(controller.tableView.numberOfRows(inSection: 0) == 4)
    }

    @Test func `perform stays pending for a row that has not arrived yet`() {
        let controller = makeController()
        let chatVM = makeChatVM()

        #expect(controller.perform(.message(999, anchor: .top, animated: false)) == false)
    }

    @Test func `perform succeeds once the target row has been applied`() async {
        let controller = makeController()
        let chatVM = makeChatVM()
        let messages = makeMessages(count: 3, chatVM: chatVM)

        controller.update(makeConfiguration(chatVM: chatVM, messages: messages))
        await waitUntilRowCount(controller, equals: 4)

        #expect(controller.perform(.message(messages[1].id, anchor: .top, animated: false)))
    }

    @Test func `the navigator flushes a queued scroll request once the controller attaches`() async {
        let navigator = ChatHistoryNavigator()
        let chatVM = makeChatVM()
        let messages = makeMessages(count: 3, chatVM: chatVM)

        // Submitted before any controller exists, exactly like `ChatView` calling `scrollToBottom`
        // before its `UIViewControllerRepresentable` has finished creating the row it targets.
        navigator.scrollToBottom(animated: false)

        let controller = ChatHistoryTableViewController(navigator: navigator)
        controller.update(makeConfiguration(chatVM: chatVM, messages: messages))
        await waitUntilRowCount(controller, equals: 4)

        // `viewDidLayoutSubviews` is where production re-flushes the navigator after layout - the
        // representable calls `loadViewIfNeeded()` then relies on that pass to happen.
        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 800)
        controller.view.layoutIfNeeded()
        controller.viewDidLayoutSubviews()

        // If the request never flushed, this would still be the identity `.top` position rather
        // than the bottom one the queued request asked for.
        #expect(controller.perform(.bottom(animated: false)))
    }

    @Test func `scroll button state reflects whether the last message is visible`() async {
        let controller = makeController()
        let chatVM = makeChatVM()
        let messages = makeMessages(count: 40, chatVM: chatVM)

        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 500)
        controller.update(makeConfiguration(chatVM: chatVM, messages: messages))
        await waitUntilRowCount(controller, equals: 40)
        controller.view.layoutIfNeeded()

        // `scrollToRow` to a far-away, never-measured row lands using UIKit's *estimated* row
        // height the first time; a second pass re-targets using the now-actual heights it just
        // measured, which is what settles it within the 20pt "at bottom" tolerance.
        _ = controller.perform(.bottom(animated: false))
        controller.tableView.layoutIfNeeded()
        _ = controller.perform(.bottom(animated: false))
        #expect(chatVM.showScrollToBottomButton == false)

        _ = controller.perform(.message(messages[0].id, anchor: .top, animated: false))
        #expect(chatVM.showScrollToBottomButton)
    }

    @Test func `visible rows are reported as viewed once mark-as-read is enabled`() async {
        let controller = makeController()
        let chatVM = makeChatVM()
        let messages = makeMessages(count: 3, chatVM: chatVM)

        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 800)
        controller.update(makeConfiguration(
            chatVM: chatVM,
            messages: messages,
            isPreview: false,
            canMarkMessagesRead: false,
        ))
        await waitUntilRowCount(controller, equals: 4)
        controller.view.layoutIfNeeded()

        #expect(chatVM.pendingViewedMessageIds.isEmpty)

        controller.update(makeConfiguration(
            chatVM: chatVM,
            messages: messages,
            isPreview: false,
            canMarkMessagesRead: true,
        ))

        #expect(chatVM.pendingViewedMessageIds.contains(messages[0].id))
        #expect(chatVM.pendingViewedMessageIds.contains(messages[2].id))
    }

    /// A height-only resize (the keyboard opening or closing) can move a conversation across the
    /// "shorter than the viewport" threshold, which changes `contentInset.top`. Verifies
    /// `contentOffset` still ends up inside the newly valid scroll range instead of stuck
    /// somewhere now-invalid - it does not have to matter *which* code path clamps it (UIKit's own
    /// `UIScrollView` layout pass does this on its own here), only that the end state is correct.
    @Test func `a height-only resize leaves the content offset within the valid scroll range`() async {
        let controller = makeController()
        let chatVM = makeChatVM()
        let messages = makeMessages(count: 12, chatVM: chatVM)

        // Measure the real (self-sized) content height with a generous viewport first, so the two
        // viewport sizes below can be placed reliably on either side of it.
        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 4000)
        controller.update(makeConfiguration(chatVM: chatVM, messages: messages))
        await waitUntilRowCount(controller, equals: 13)
        controller.view.layoutIfNeeded()
        controller.tableView.layoutIfNeeded()
        let contentHeight = controller.tableView.contentSize.height
        #expect(contentHeight > 0)

        let smallHeight = max(100, contentHeight - 150)
        let largeHeight = contentHeight + 150

        // Small viewport (content taller than it - fully scrollable), scrolled to the very top.
        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: smallHeight)
        controller.view.layoutIfNeeded()
        controller.viewDidLayoutSubviews()
        _ = controller.perform(.message(messages[0].id, anchor: .top, animated: false))
        let offsetBefore = controller.tableView.contentOffset.y

        // Large viewport (content now shorter than it) - simulates the keyboard dismissing.
        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: largeHeight)
        controller.view.layoutIfNeeded()
        controller.viewDidLayoutSubviews()
        let offsetAfter = controller.tableView.contentOffset.y

        // The valid range collapses to a single point once content fits the viewport.
        let expectedOffset = -(largeHeight - controller.tableView.contentSize.height)
        #expect(abs(offsetAfter - expectedOffset) < 2)
        #expect(offsetBefore != offsetAfter) // sanity: the resize actually did something
    }

    // MARK: Private

    private func makeController() -> ChatHistoryTableViewController {
        ChatHistoryTableViewController(navigator: ChatHistoryNavigator())
    }

    private func makeChatVM() -> ChatVM {
        let user = TDLibFixtures.user(id: 1)
        let customChat = CustomChat(
            chat: TDLibFixtures.chat(id: 1, order: 1),
            position: TDLibFixtures.position(order: 1),
            unreadCount: 0,
            type: .user(user),
        )
        return ChatVM(customChat: customChat, service: FakeTelegramService())
    }

    private func makeMessages(count: Int, chatVM _: ChatVM) -> [CustomMessage] {
        let baseDate = 1_700_000_000
        return (0..<count).map { index in
            CustomMessage(
                message: TDLibFixtures.message(
                    id: Int64(index + 1),
                    chatId: 1,
                    date: baseDate + index * 60,
                    text: "Message \(index)",
                ),
                properties: .default,
            )
        }
    }

    private func makeConfiguration(
        chatVM: ChatVM,
        messages: [CustomMessage],
        isPreview: Bool = true,
        canLoadOlderMessages: Bool = false,
        canMarkMessagesRead: Bool = false,
    ) -> ChatHistoryTableViewController.Configuration {
        ChatHistoryTableViewController.Configuration(
            chatVM: chatVM,
            messages: messages,
            unreadMessageId: nil,
            unreadCount: 0,
            currentUnreadCount: 0,
            unreadHeaderVoiceOverFocusRequest: 0,
            shouldShowProfileImage: false,
            isPreview: isPreview,
            canLoadOlderMessages: canLoadOlderMessages,
            canMarkMessagesRead: canMarkMessagesRead,
            messageAccessibilityFocused: accessibilityFocusHost.$focusedMessageId,
            dynamicTypeSize: .large,
            bubbleCornerRadius: 16,
            colorScheme: .dark,
            layoutDirection: .leftToRight,
            reduceMotion: false,
            onBackgroundTap: {},
            onScrollButtonFocused: {},
        )
    }

    private let accessibilityFocusHost = AccessibilityFocusHost()

    private func waitUntilRowCount(
        _ controller: ChatHistoryTableViewController,
        equals expected: Int,
        maxAttempts: Int = 200,
    ) async {
        for _ in 0..<maxAttempts {
            if controller.tableView.numberOfRows(inSection: 0) == expected { return }
            await Task.yield()
        }
    }
}

// MARK: - AccessibilityFocusHost

/// `AccessibilityFocusState` is a `DynamicProperty`, but its storage works like any other property
/// wrapper - it doesn't require being embedded in a live `View` body to produce a usable `Binding`
/// for a `Configuration` under test.
private struct AccessibilityFocusHost {
    @AccessibilityFocusState var focusedMessageId: Int64?
}
