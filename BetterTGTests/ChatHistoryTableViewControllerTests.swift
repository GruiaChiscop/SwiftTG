// ChatHistoryTableViewControllerTests.swift

@testable import BetterTG
import SwiftUI
import Testing
import UIKit

// MARK: - ChatHistoryTableViewControllerTests

@MainActor struct ChatHistoryTableViewControllerTests {
    // MARK: Internal

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

    @Test func `unread navigation remains pending until the table has a viewport`() async throws {
        let navigator = ChatHistoryNavigator()
        let controller = ChatHistoryTableViewController(navigator: navigator)
        let vm = makeChatVM()
        let messages = makeMessages(count: 10, chatVM: vm)
        navigator.scrollToUnreadHeader(startingAt: messages[4].id)
        controller.update(makeConfiguration(chatVM: vm, messages: messages, unreadMessageId: messages[4].id))
        await waitUntilRowCount(controller, equals: 12)
        #expect(navigator.hasPendingRequest)
        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 400)
        controller.view.layoutIfNeeded()
        controller.viewDidLayoutSubviews()
        #expect(!navigator.hasPendingRequest)
        let path = try #require(controller.dataSource.indexPath(for: .unread(messages[4].id)))
        #expect(controller.tableView.rectForRow(at: path).intersects(controller.tableView.bounds))
    }

    @Test func `native unread focus survives reconfiguration without being requested twice`() async {
        var jobs = [@MainActor @Sendable () -> Void]()
        var posts = [UIView]()
        let focus = VoiceOverFocusController(
            isVoiceOverRunning: { true },
            schedule: { jobs.append($0) },
            postFocus: { posts.append($0) },
            waitForTransition: { _, _ in false },
        )
        let navigator = ChatHistoryNavigator()
        let controller = ChatHistoryTableViewController(navigator: navigator, focusController: focus)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 500))
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }
        controller.view.frame = window.bounds
        let vm = makeChatVM()
        let messages = makeMessages(count: 10, chatVM: vm)
        navigator.scrollToUnreadHeader(startingAt: messages[4].id)
        let config = makeConfiguration(
            chatVM: vm,
            messages: messages,
            isPreview: false,
            unreadMessageId: messages[4].id,
            unreadRequest: 1,
        )
        controller.update(config)
        await waitUntilRowCount(controller, equals: 12)
        controller.view.layoutIfNeeded()
        controller.viewDidAppear(false)
        while !jobs.isEmpty {
            jobs.removeFirst()()
        }
        #expect(posts.count == 1)
        let header = posts.first
        #expect(header?.accessibilityLabel == "20 unread messages")
        #expect(header?.accessibilityTraits.contains(.header) == true)
        controller.update(config)
        controller.viewDidLayoutSubviews()
        while !jobs.isEmpty {
            jobs.removeFirst()()
        }
        #expect(posts.count == 1)
        #expect(header?.window === window)
    }

    @Test func `initial read receipt requires a non-preview active conversation`() async {
        let controller = makeController()
        let vm = makeChatVM()
        vm.initialUnreadCount = 159
        vm.initialReadThroughMessageId = 200
        vm.initialMessagesLoaded = true
        let messages = makeMessages(count: 3, chatVM: vm)
        controller.update(makeConfiguration(chatVM: vm, messages: messages, isPreview: true, canMarkMessagesRead: true))
        await waitUntilRowCount(controller, equals: 4)
        controller.view.layoutIfNeeded()
        #expect(vm.initialReadTask == nil)
        controller.update(makeConfiguration(
            chatVM: vm,
            messages: messages,
            isPreview: false,
            canMarkMessagesRead: false,
        ))
        #expect(vm.initialReadTask == nil)
        controller.update(makeConfiguration(
            chatVM: vm,
            messages: messages,
            isPreview: false,
            canMarkMessagesRead: true,
        ))
        // Changing preview state applies a snapshot; the immediately following read-enabled
        // configuration must not invalidate its pending completion and lose the receipt.
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        await vm.initialReadTask?.value
        #expect(vm.didMarkInitialMessagesRead)
    }

    @Test func `initial positioning is acknowledged only after table appearance with a visible target`() async throws {
        let navigator = ChatHistoryNavigator()
        let controller = ChatHistoryTableViewController(navigator: navigator)
        let vm = makeChatVM()
        let messages = makeMessages(count: 10, chatVM: vm)
        var acknowledgements = 0
        navigator.positionInitially(.unread(messages[4].id)) { result in
            if case .positioned = result {
                acknowledgements += 1
            }
        }
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 500)
        controller.update(makeConfiguration(chatVM: vm, messages: messages, unreadMessageId: messages[4].id))
        await waitUntilRowCount(controller, equals: 12)
        controller.view.layoutIfNeeded()
        #expect(navigator.hasPendingInitialPosition)
        #expect(acknowledgements == 0)
        let window = UIWindow(frame: controller.view.frame)
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }
        controller.view.layoutIfNeeded()
        controller.viewDidAppear(false)
        #expect(!navigator.hasPendingRequest)
        #expect(acknowledgements == 1)
        let path = try #require(controller.dataSource.indexPath(for: .unread(messages[4].id)))
        #expect(controller.tableView.cellForRow(at: path).map(VoiceOverFocusController.isVisible) == true)
        controller.viewDidLayoutSubviews()
        navigator.flushPendingRequest()
        #expect(acknowledgements == 1)
    }

    @Test func `an empty conversation completes initial positioning for composer focus`() async {
        let navigator = ChatHistoryNavigator()
        let controller = ChatHistoryTableViewController(navigator: navigator)
        var positioned = false
        navigator.positionInitially(.bottom(animated: false)) { result in
            if case .positioned = result {
                positioned = true
            }
        }
        controller.update(makeConfiguration(chatVM: makeChatVM(), messages: []))
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 500))
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }
        controller.view.frame = window.bounds
        controller.view.layoutIfNeeded()
        controller.viewDidAppear(false)
        #expect(positioned)
        #expect(!navigator.hasPendingRequest)
    }

    // MARK: Private

    private let accessibilityFocusHost = AccessibilityFocusHost()

    private func makeController() -> ChatHistoryTableViewController {
        let controller = ChatHistoryTableViewController(navigator: ChatHistoryNavigator())
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 800)
        controller.view.layoutIfNeeded()
        return controller
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
        unreadMessageId: Int64? = nil,
        unreadRequest: Int = 0,
        dynamicTypeSize: DynamicTypeSize = .large,
    ) -> ChatHistoryTableViewController.Configuration {
        ChatHistoryTableViewController.Configuration(
            chatVM: chatVM,
            messages: messages,
            unreadMessageId: unreadMessageId,
            unreadCount: unreadMessageId == nil ? 0 : 20,
            currentUnreadCount: 0,
            unreadHeaderVoiceOverFocusRequest: unreadRequest,
            shouldShowProfileImage: false,
            isPreview: isPreview,
            canLoadOlderMessages: canLoadOlderMessages,
            canMarkMessagesRead: canMarkMessagesRead,
            messageAccessibilityFocused: accessibilityFocusHost.$focusedMessageId,
            dynamicTypeSize: dynamicTypeSize,
            bubbleCornerRadius: 16,
            colorScheme: .dark,
            layoutDirection: .leftToRight,
            reduceMotion: false,
            onBackgroundTap: {},
            onScrollButtonFocused: {},
        )
    }

    private func waitUntilRowCount(
        _ controller: ChatHistoryTableViewController,
        equals expected: Int,
        maxAttempts: Int = 200,
    ) async {
        for _ in 0..<maxAttempts {
            if controller.tableView.numberOfRows(inSection: 0) == expected {
                return
            }
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
