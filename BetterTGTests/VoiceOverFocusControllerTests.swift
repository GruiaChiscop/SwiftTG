// VoiceOverFocusControllerTests.swift

@testable import BetterTG
import Testing
import UIKit

@MainActor struct VoiceOverFocusControllerTests {
    // MARK: Internal

    @Test func `request waits for the target to acquire visible geometry`() {
        let harness = Harness()
        harness.target.frame = .zero
        harness.controller.requestFocus(on: harness.target)
        #expect(harness.jobs.isEmpty)
        harness.target.frame = CGRect(x: 10, y: 10, width: 200, height: 40)
        harness.controller.viewDidLayout(harness.target)
        #expect(harness.posts.isEmpty)
        harness.drain()
        #expect(harness.posts == [harness.target])
    }

    @Test func `request made before mounting survives until window attachment`() {
        let harness = Harness()
        harness.target.removeFromSuperview()
        harness.controller.requestFocus(on: harness.target)
        #expect(harness.jobs.isEmpty)
        harness.window.addSubview(harness.target)
        harness.controller.viewDidMoveToWindow(harness.target)
        harness.drain()
        #expect(harness.posts == [harness.target])
    }

    @Test func `cancelled transition callback cannot restore an old request`() {
        let harness = Harness()
        harness.hasTransition = true
        harness.controller.requestFocus(on: harness.target)
        harness.controller.cancel()
        harness.transitionCompletion?(false)
        harness.drain()
        #expect(harness.posts.isEmpty)
    }

    @Test func `focus waits for navigation completion and the next main queue turn`() {
        let harness = Harness()
        harness.hasTransition = true
        harness.controller.requestFocus(on: harness.target)
        #expect(harness.jobs.isEmpty)
        harness.transitionCompletion?(false)
        #expect(harness.posts.isEmpty)
        harness.drain()
        #expect(harness.posts == [harness.target])
    }

    @Test func `interactive navigation cancellation drops focus`() {
        let harness = Harness()
        harness.hasTransition = true
        harness.controller.requestFocus(on: harness.target)
        harness.transitionCompletion?(true)
        harness.drain()
        #expect(harness.posts.isEmpty)
    }

    @Test func `new request invalidates queued delivery to the old target`() {
        let harness = Harness()
        let replacement = UIView(frame: harness.target.frame)
        harness.window.addSubview(replacement)
        harness.controller.requestFocus(on: harness.target)
        harness.controller.requestFocus(on: replacement)
        harness.drain()
        #expect(harness.posts == [replacement])
    }

    @Test func `removing the target before delivery cancels the request`() {
        let harness = Harness()
        harness.controller.requestFocus(on: harness.target)
        harness.target.removeFromSuperview()
        harness.controller.viewDidMoveToWindow(harness.target)
        harness.window.addSubview(harness.target)
        harness.controller.viewDidMoveToWindow(harness.target)
        harness.drain()
        #expect(harness.posts.isEmpty)
    }

    @Test func `late banner layout changes do not repeat a delivered focus request`() {
        let harness = Harness()
        harness.controller.requestFocus(on: harness.target)
        harness.drain()
        harness.target.frame.origin.y += 50
        harness.controller.viewDidLayout(harness.target)
        harness.drain()
        #expect(harness.posts == [harness.target])
    }

    @Test func `rejected transition registration cannot post twice on late completion`() {
        let harness = Harness()
        harness.controller.requestFocus(on: harness.target)
        harness.drain()
        harness.transitionCompletion?(false)
        harness.drain()
        #expect(harness.posts == [harness.target])
    }

    @Test func `turning off VoiceOver before delivery discards the request`() {
        let harness = Harness()
        harness.controller.requestFocus(on: harness.target)
        harness.voiceOverRunning = false
        harness.drain()
        #expect(harness.posts.isEmpty)
    }

    @Test func `target clipped outside the history viewport is not ready`() {
        let harness = Harness()
        let viewport = UIView(frame: CGRect(x: 0, y: 0, width: 300, height: 100))
        viewport.clipsToBounds = true
        harness.window.addSubview(viewport)
        viewport.addSubview(harness.target)
        harness.target.frame.origin.y = 150
        #expect(!VoiceOverFocusController.isVisible(harness.target))
        harness.target.frame.origin.y = 20
        #expect(VoiceOverFocusController.isVisible(harness.target))
    }

    @Test func `a snapshot starting before queued focus delivery defers that delivery`() {
        let harness = Harness()
        var snapshotApplied = true
        harness.controller.requestFocus(on: harness.target, canDeliver: { snapshotApplied })
        snapshotApplied = false
        harness.drain()
        #expect(harness.posts.isEmpty)
        snapshotApplied = true
        harness.controller.viewDidLayout(harness.target)
        harness.drain()
        #expect(harness.posts == [harness.target])
    }

    // MARK: Private

    @MainActor private final class Harness {
        // MARK: Lifecycle

        init() {
            window.isHidden = false
            window.addSubview(target)
        }

        // MARK: Internal

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 800))
        let target = UIView(frame: CGRect(x: 10, y: 10, width: 200, height: 40))
        var jobs = [@MainActor @Sendable () -> Void]()
        var posts = [UIView]()
        var voiceOverRunning = true
        var hasTransition = false
        var transitionCompletion: (@MainActor (Bool) -> Void)?

        lazy var controller = VoiceOverFocusController(
            isVoiceOverRunning: { [unowned self] in voiceOverRunning },
            schedule: { [unowned self] in jobs.append($0) },
            postFocus: { [unowned self] in posts.append($0) },
            waitForTransition: { [unowned self] _, completion in
                transitionCompletion = completion
                return hasTransition
            },
        )

        func drain() {
            while !jobs.isEmpty {
                jobs.removeFirst()()
            }
        }
    }
}
