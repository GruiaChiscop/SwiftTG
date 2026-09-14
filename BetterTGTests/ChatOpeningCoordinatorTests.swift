// ChatOpeningCoordinatorTests.swift

@testable import BetterTG
import Testing

@MainActor struct ChatOpeningCoordinatorTests {
    // MARK: Internal

    @Test(arguments: [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]])
    func `opening waits for history layout and appearance in any order`(events: [Int]) {
        let harness = Harness()
        for (index, event) in events.enumerated() {
            switch event {
            case 0:
                harness.target.hasRows = true
                harness.begin()
            case 1: harness.target.hasViewport = true
            default: harness.target.hasAppeared = true
            }
            harness.navigator.flushPendingRequest()
            // UIKit's callback never mutates observed presentation state inside its layout pass.
            #expect(!harness.opening.isReady)
            harness.drain()
            #expect(harness.opening.isReady == (index == 2))
            #expect(harness.opening.unreadFocusRequest == (index == 2 ? 1 : 0))
        }
        #expect(harness.target.initialPositions == 1)
    }

    @Test func `later data and layout updates cannot restart a completed opening`() {
        let harness = Harness()
        harness.target.makeReady()
        harness.begin()
        harness.drain()
        harness.opening.begin(
            plan: .make(
                initialMessageId: nil,
                movesFocusToInitialMessage: false,
                unreadMessageId: 5,
                lastMessageId: 100,
                canCompose: true,
            ),
            navigator: harness.navigator,
            allowsFocus: true,
        )
        harness.navigator.flushPendingRequest()
        harness.drain()
        #expect(harness.opening.plan?.unreadMessageId == 20)
        #expect(harness.target.initialPositions == 1)
    }

    @Test func `leaving before deferred acknowledgement prevents late focus and reading`() {
        let harness = Harness()
        harness.target.makeReady()
        harness.begin()
        harness.opening.leave(navigator: harness.navigator)
        harness.drain()
        #expect(!harness.opening.isReady)
        #expect(harness.opening.focusTarget == .none)
        #expect(!harness.navigator.hasPendingRequest)
    }

    @Test func `a new navigation supersedes pending initial positioning without stealing focus`() {
        let harness = Harness()
        harness.begin()
        harness.navigator.scrollToMessage(77, anchor: .center, animated: false)
        harness.drain()
        #expect(harness.opening.isReady)
        #expect(harness.opening.focusTarget == .none)
        #expect(harness.target.initialPositions == 0)
        #expect(harness.target.explicitPositions == 1)
    }

    @Test func `resuming waits for a fresh acknowledgement and ignores the old one`() {
        let harness = Harness()
        harness.target.makeReady()
        harness.begin()
        harness.opening.leave(navigator: harness.navigator)
        harness.target.hasAppeared = false
        harness.begin()
        harness.drain()
        #expect(harness.opening.phase == .positioning)
        harness.target.hasAppeared = true
        harness.navigator.flushPendingRequest()
        harness.drain()
        #expect(harness.opening.isReady)
        #expect(harness.opening.focusTarget == .none)
    }

    @Test func `preview or disabled VoiceOver allows positioning without requesting focus`() {
        let harness = Harness()
        harness.target.makeReady()
        harness.begin(allowsFocus: false)
        harness.drain()
        #expect(harness.opening.isReady)
        #expect(harness.opening.focusTarget == .none)
    }

    @Test func `empty writable conversations choose composer and unread chats choose header`() {
        let empty = ChatOpeningCoordinator.Plan.make(
            initialMessageId: nil,
            movesFocusToInitialMessage: false,
            unreadMessageId: nil,
            lastMessageId: nil,
            canCompose: true,
        )
        #expect(empty.focus == .composer)
        let unread = ChatOpeningCoordinator.Plan.make(
            initialMessageId: nil,
            movesFocusToInitialMessage: false,
            unreadMessageId: 20,
            lastMessageId: 100,
            canCompose: true,
        )
        #expect(unread.focus == .unreadHeader)
    }

    @Test func `explicit links preserve the requested focus policy`() {
        let withoutFocus = ChatOpeningCoordinator.Plan.make(
            initialMessageId: 77,
            movesFocusToInitialMessage: false,
            unreadMessageId: 20,
            lastMessageId: 100,
            canCompose: true,
        )
        #expect(withoutFocus.focus == .none)
        let withFocus = ChatOpeningCoordinator.Plan.make(
            initialMessageId: 77,
            movesFocusToInitialMessage: true,
            unreadMessageId: 20,
            lastMessageId: 100,
            canCompose: true,
        )
        #expect(withFocus.focus == .message(77))
    }

    // MARK: Private

    @MainActor private final class Harness {
        var jobs = [@MainActor @Sendable () -> Void]()
        let target = Target()
        let navigator = ChatHistoryNavigator()
        lazy var opening = ChatOpeningCoordinator(schedule: { [unowned self] in jobs.append($0) })

        func begin(allowsFocus: Bool = true) {
            navigator.attach(target)
            opening.begin(
                plan: .make(
                    initialMessageId: nil,
                    movesFocusToInitialMessage: false,
                    unreadMessageId: 20,
                    lastMessageId: 100,
                    canCompose: true,
                ),
                navigator: navigator,
                allowsFocus: allowsFocus,
            )
        }

        func drain() {
            while !jobs.isEmpty {
                jobs.removeFirst()()
            }
        }
    }

    @MainActor private final class Target: ChatHistoryNavigating {
        var hasRows = false
        var hasViewport = false
        var hasAppeared = false
        var initialPositions = 0
        var explicitPositions = 0

        func makeReady() {
            hasRows = true
            hasViewport = true
            hasAppeared = true
        }

        func performInitial(_: ChatHistoryNavigator.Request) -> Bool {
            guard hasRows, hasViewport, hasAppeared else { return false }
            initialPositions += 1
            return true
        }

        func perform(_: ChatHistoryNavigator.Request) -> Bool {
            explicitPositions += 1
            return true
        }
    }
}
