// StableTranslationBannerLabel.swift

import SwiftUI
import UIKit

// MARK: - StableTranslationBannerLabel

/// Keeps one native accessibility element mounted while message rows finish rendering below it.
/// See `StableIconButton` for the root cause and the equivalent fix for tappable icons.
struct StableTranslationBannerLabel: UIViewRepresentable {
    let text: String

    func makeUIView(context _: Context) -> UILabel {
        let label = UILabel()
        label.adjustsFontForContentSizeCategory = true
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.numberOfLines = 0
        label.textColor = .label
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return label
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView label: UILabel, context _: Context) -> CGSize? {
        guard let width = proposal.width, width > 0, width.isFinite else { return nil }
        let size = label.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(size.height))
    }

    func updateUIView(_ label: UILabel, context _: Context) {
        guard label.text != text else { return }
        label.text = text
    }
}
