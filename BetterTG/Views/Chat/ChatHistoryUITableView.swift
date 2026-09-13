// ChatHistoryUITableView.swift

import UIKit

// MARK: - ChatHistoryUITableView

/// Reports self-sizing changes after UIKit has finished its current layout pass.
@MainActor final class ChatHistoryUITableView: UITableView {
    // MARK: Internal

    override var contentSize: CGSize {
        didSet {
            guard contentSize != oldValue, !contentSizeNotificationScheduled else { return }
            contentSizeNotificationScheduled = true
            // `DispatchQueue.main.async`, not `Task { await Task.yield() }`: the main actor's
            // executor doesn't resume a freshly spawned task's continuation in a fixed number of
            // yields, so a yield-based coalesce is not reliably "after this runloop turn" - it
            // sometimes lands a turn later than callers (and tests) expect. Posting to the main
            // queue directly is deterministic: it runs once the current synchronous UIKit layout
            // pass (which is what drives repeated `contentSize` writes) has finished.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                contentSizeNotificationScheduled = false
                onContentSizeChange?()
            }
        }
    }

    var onContentSizeChange: (() -> Void)?

    // MARK: Private

    private var contentSizeNotificationScheduled = false
}
