// VoiceOverFocusController.swift

import UIKit

// MARK: - VoiceOverFocusController

/// Delivers one initial-focus request after the target is visible and navigation has finished.
/// Every deferred callback belongs to a generation, including UIKit transition completions,
/// so cancellation or reuse cannot resurrect a stale request.
@MainActor final class VoiceOverFocusController {
    // MARK: Lifecycle

    init(
        isVoiceOverRunning: @escaping () -> Bool = { UIAccessibility.isVoiceOverRunning },
        schedule: @escaping (@escaping @MainActor @Sendable () -> Void) -> Void = { work in
            DispatchQueue.main.async(execute: work)
        },
        // `.layoutChanged` skips the full-screen accessibility-tree rescan that `.screenChanged`
        // triggers - on a chat with many rows that rescan measurably delayed VoiceOver actually
        // landing on the target, by up to ~1.3s in practice (any audible cue is the system's own
        // decision either way, not something either notification dictates).
        postFocus: @escaping (UIView) -> Void = {
            UIAccessibility.post(notification: .layoutChanged, argument: $0)
        },
        waitForTransition: @escaping (UIView, @escaping @MainActor (Bool) -> Void) -> Bool = { view, completion in
            let controller = sequence(first: view.next, next: { $0?.next })
                .first { $0 is UIViewController } as? UIViewController
            guard let transition = controller?.transitionCoordinator else { return false }
            return transition.animate(alongsideTransition: nil) { context in
                completion(context.isCancelled)
            }
        },
    ) {
        self.isVoiceOverRunning = isVoiceOverRunning
        self.schedule = schedule
        self.postFocus = postFocus
        self.waitForTransition = waitForTransition
    }

    // MARK: Internal

    static func isVisible(_ view: UIView) -> Bool {
        guard let window = view.window, !view.bounds.isEmpty,
              view.convert(view.bounds, to: window).intersects(window.bounds)
        else { return false }
        var ancestor: UIView? = view
        while let current = ancestor {
            guard !current.isHidden, current.alpha > 0.01 else { return false }
            if current.clipsToBounds,
               !view.convert(view.bounds, to: current).intersects(current.bounds)
            {
                return false
            }
            ancestor = current.superview
        }
        return true
    }

    func cancel() {
        generation &+= 1
        pendingView = nil
        onDelivery = nil
        canDeliver = nil
        waitingForTransition = false
        transitionFinished = false
        deliveryScheduled = false
    }

    func requestFocus(
        on view: UIView,
        canDeliver: @escaping () -> Bool = { true },
        onDelivery: @escaping () -> Void = {},
    ) {
        cancel()
        guard isVoiceOverRunning() else { return }
        pendingView = view
        self.onDelivery = onDelivery
        self.canDeliver = canDeliver
        chatScrollTrace("initial focus requested: \(view.accessibilityLabel ?? String(describing: type(of: view)))")
        performPendingRequestIfPossible()
    }

    func viewDidMoveToWindow(_ view: UIView) {
        guard pendingView === view else { return }
        if view.window == nil {
            cancel()
        } else {
            performPendingRequestIfPossible()
        }
    }

    func viewDidLayout(_ view: UIView) {
        guard pendingView === view else { return }
        performPendingRequestIfPossible()
    }

    // MARK: Private

    private let isVoiceOverRunning: () -> Bool
    private let schedule: (@escaping @MainActor @Sendable () -> Void) -> Void
    private let postFocus: (UIView) -> Void
    private let waitForTransition: (UIView, @escaping @MainActor (Bool) -> Void) -> Bool
    private weak var pendingView: UIView?
    private var onDelivery: (() -> Void)?
    private var canDeliver: (() -> Bool)?
    private var generation = 0
    private var waitingForTransition = false
    private var transitionFinished = false
    private var deliveryScheduled = false

    private func performPendingRequestIfPossible() {
        guard let view = pendingView, Self.isVisible(view), canDeliver?() != false,
              !waitingForTransition, !deliveryScheduled
        else { return }
        let requestGeneration = generation
        if !transitionFinished {
            waitingForTransition = true
            let registered = waitForTransition(view) { [weak self] cancelled in
                guard let self, generation == requestGeneration, pendingView != nil else { return }
                waitingForTransition = false
                transitionFinished = true
                if cancelled {
                    cancel()
                } else {
                    performPendingRequestIfPossible()
                }
            }
            guard generation == requestGeneration, pendingView != nil else { return }
            if registered {
                return
            }
            // UIKit can refuse registration near the end of a transition. Its completion may
            // still arrive; generation and delivery guards make that callback harmless.
            waitingForTransition = false
            transitionFinished = true
        }
        guard !deliveryScheduled else { return }
        deliveryScheduled = true
        // Enqueue after the current UIKit layout/transition callbacks, rather than yielding an
        // actor task (which can resume before that work). No repeated posts after delivery.
        schedule { [weak self] in
            guard let self, generation == requestGeneration else { return }
            deliveryScheduled = false
            guard let view = pendingView, Self.isVisible(view), canDeliver?() != false else { return }
            guard isVoiceOverRunning() else {
                cancel()
                return
            }
            let delivered = onDelivery
            cancel()
            delivered?()
            chatScrollTrace("initial focus posted: \(view.accessibilityLabel ?? String(describing: type(of: view)))")
            postFocus(view)
        }
    }
}
