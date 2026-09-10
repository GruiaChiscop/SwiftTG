// ChatHistoryUICollectionView.swift

import UIKit

// MARK: - ChatHistoryUICollectionView

/// Keeps UIKit in charge of touch and VoiceOver scrolling. In particular, do not override
/// `accessibilityScroll`: `UICollectionView` already pages its viewport and coordinates focus with
/// cells that enter and leave the accessibility hierarchy.
@MainActor final class ChatHistoryUICollectionView: UICollectionView {
    override var contentOffset: CGPoint {
        get { super.contentOffset }
        set {
            // UIKit occasionally resets a collection view to zero before its first layout has
            // established a content size. Signal applies the same guard to its conversation view.
            guard contentSize.height >= 1 || newValue.y > 0 else { return }
            super.contentOffset = newValue
        }
    }
}
