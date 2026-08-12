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

    func updateUIView(_ label: UILabel, context _: Context) {
        guard label.text != text else { return }
        label.text = text
    }
}
