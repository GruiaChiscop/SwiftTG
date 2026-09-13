// MessagePreviewHeightLayout.swift

import SwiftUI

/// Unlike a flexible max-height frame, supplies a finite proposal even when a self-sizing row
/// asks for its ideal (unspecified) height. Reports the chosen preview's natural height so short
/// messages don't acquire empty space.
struct MessagePreviewHeightLayout: Layout {
    let maximumHeight: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        subviews.first?.sizeThatFits(ProposedViewSize(width: proposal.width, height: maximumHeight)) ?? .zero
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        subviews.first?.place(
            at: bounds.origin,
            proposal: ProposedViewSize(width: bounds.width, height: maximumHeight),
        )
    }
}
