// ChatHistoryTableCell.swift

import SwiftUI
import UIKit

// MARK: - ChatHistoryTableCell

@MainActor final class ChatHistoryTableCell: UITableViewCell {
    // MARK: Lifecycle

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        selectionStyle = .none
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Internal

    static let reuseIdentifier = "ChatHistoryTableCell"

    func configure(rootView: some View) {
        contentConfiguration = UIHostingConfiguration {
            rootView
        }
        .margins(.all, 0)
        .minSize(height: 1)
        .background(Color.clear)
    }
}
