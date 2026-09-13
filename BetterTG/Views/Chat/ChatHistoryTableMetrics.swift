// ChatHistoryTableMetrics.swift

import CoreGraphics

// MARK: - ChatHistoryTableMetrics

enum ChatHistoryTableMetrics {
    struct ScrollState: Equatable {
        let isAtBottom: Bool
        let shouldShowBottomButton: Bool
    }

    static func topContentInset(contentHeight: CGFloat, viewportHeight: CGFloat) -> CGFloat {
        max(0, viewportHeight - contentHeight)
    }

    static func scrollState(
        contentHeight: CGFloat,
        viewportHeight: CGFloat,
        topInset: CGFloat,
        bottomInset: CGFloat,
        contentOffsetY: CGFloat,
    ) -> ScrollState {
        let minimumOffsetY = -topInset
        let maximumOffsetY = max(
            minimumOffsetY,
            contentHeight - viewportHeight + bottomInset,
        )
        let distanceFromBottom = maximumOffsetY - contentOffsetY
        let pageHeight = max(1, viewportHeight - topInset - bottomInset)
        return ScrollState(
            isAtBottom: distanceFromBottom < 20,
            shouldShowBottomButton: distanceFromBottom > pageHeight,
        )
    }

    static func itemsBeforeAnchorChanged<ID: Equatable>(
        _ anchorID: ID?,
        oldIDs: [ID],
        newIDs: [ID],
    ) -> Bool {
        guard let anchorID,
              let oldIndex = oldIDs.firstIndex(of: anchorID),
              let newIndex = newIDs.firstIndex(of: anchorID)
        else { return false }
        return oldIDs[..<oldIndex] != newIDs[..<newIndex]
    }
}
