// ChatHistoryHostingCell.swift

import SwiftUI
import UIKit

// MARK: - ChatHistoryHostingCell

@MainActor final class ChatHistoryHostingCell: UICollectionViewCell {
    // MARK: Lifecycle

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        contentView.backgroundColor = .clear
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Internal

    static let reuseIdentifier = "ChatHistoryHostingCell"

    func configure(rootView: AnyView) {
        contentConfiguration = UIHostingConfiguration {
            rootView
        }
        .margins(.all, 0)
    }
}
