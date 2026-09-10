// VoiceOverFocusTarget.swift

import SwiftUI

// MARK: - VoiceOverFocusTarget

/// Provides a concrete UIKit accessibility element for SwiftUI content that must become the
/// VoiceOver cursor target. `AccessibilityFocusState` can be lost while a navigation transition or
/// a surrounding SwiftUI hierarchy update is still completing; posting `layoutChanged` with the
/// actual element gives UIKit an unambiguous destination.
struct VoiceOverFocusTarget: UIViewRepresentable {
    final class Coordinator {
        var lastRequest = 0
    }

    let label: String
    let traits: UIAccessibilityTraits
    let request: Int

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context _: Context) -> VoiceOverFocusUIView {
        let view = VoiceOverFocusUIView()
        view.backgroundColor = .clear
        view.isAccessibilityElement = true
        return view
    }

    func updateUIView(_ view: VoiceOverFocusUIView, context: Context) {
        view.accessibilityLabel = label
        view.accessibilityTraits = traits
        if request == 0 {
            context.coordinator.lastRequest = 0
            view.cancelVoiceOverFocusRequest()
            return
        }
        guard request != 0, request != context.coordinator.lastRequest else { return }
        context.coordinator.lastRequest = request
        view.requestVoiceOverFocus()
    }
}

// MARK: - VoiceOverFocusUIView

final class VoiceOverFocusUIView: UIView {
    // MARK: Internal

    override func didMoveToWindow() {
        super.didMoveToWindow()
        voiceOverFocusController.viewDidMoveToWindow(self)
    }

    func requestVoiceOverFocus() {
        voiceOverFocusController.requestFocus(on: self)
    }

    func cancelVoiceOverFocusRequest() {
        voiceOverFocusController.cancel()
    }

    // MARK: Private

    private let voiceOverFocusController = VoiceOverFocusController()
}

// MARK: - VoiceOverFocusController

@MainActor final class VoiceOverFocusController {
    // MARK: Internal

    func cancel() {
        pendingView = nil
        requestTask?.cancel()
        requestTask = nil
    }

    func requestFocus(on view: UIView) {
        guard UIAccessibility.isVoiceOverRunning else { return }
        pendingView = view
        performPendingRequestIfPossible()
    }

    func viewDidMoveToWindow(_ view: UIView) {
        guard pendingView === view else { return }
        performPendingRequestIfPossible()
    }

    // MARK: Private

    private weak var pendingView: UIView?
    private var requestTask: Task<Void, Never>?

    private func performPendingRequestIfPossible() {
        guard let view = pendingView, view.window != nil else { return }
        pendingView = nil

        let perform = { [weak self, weak view] in
            guard let self, let view else { return }
            requestTask?.cancel()
            requestTask = Task { @MainActor [weak view] in
                guard let view else { return }
                // UINavigationController posts its own `screenChanged` from the transition
                // completion. Leave that callback and its queued accessibility work behind us;
                // otherwise it can run after our first successful focus and reset VoiceOver to
                // the navigation bar or the first top banner.
                await Task.yield()
                await Task.yield()
                guard !Task.isCancelled else { return }

                // Accessibility notifications are delivered asynchronously. Retry only while the
                // current layout settles, and stop as soon as VoiceOver confirms the target. This
                // handles List virtualization without creating a later focus steal.
                for attempt in 0..<3 {
                    guard !Task.isCancelled, view.window != nil else { return }
                    UIAccessibility.post(notification: .layoutChanged, argument: view)
                    await Task.yield()
                    await Task.yield()
                    if view.accessibilityElementIsFocused() {
                        return
                    }
                    if attempt < 2 {
                        try? await Task.sleep(for: .milliseconds(40))
                    }
                }
            }
        }

        if let transitionCoordinator = view.nearestViewController?.transitionCoordinator {
            transitionCoordinator.animate(alongsideTransition: nil) { _ in perform() }
        } else {
            perform()
        }
    }
}

private extension UIView {
    var nearestViewController: UIViewController? {
        sequence(first: next, next: { $0?.next })
            .first { $0 is UIViewController } as? UIViewController
    }
}
