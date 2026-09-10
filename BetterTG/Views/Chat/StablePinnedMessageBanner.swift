// StablePinnedMessageBanner.swift

import SwiftUI
import UIKit

// MARK: - StablePinnedMessageBanner

/// Keeps the pinned-message controls inside one persistent UIKit accessibility subtree while the
/// SwiftUI message list repeatedly relays out self-sizing rows below it.
struct StablePinnedMessageBanner: UIViewRepresentable {
    // MARK: - Coordinator

    final class Coordinator {
        // MARK: Lifecycle

        init(openMessage: @escaping () -> Void, showAllMessages: @escaping () -> Void) {
            self.openMessage = openMessage
            self.showAllMessages = showAllMessages
        }

        // MARK: Internal

        var openMessage: () -> Void
        var showAllMessages: () -> Void

        @objc func performOpenMessage() {
            openMessage()
        }

        @objc func performShowAllMessages() {
            showAllMessages()
        }
    }

    // MARK: - BannerView

    final class BannerView: UIView {
        // MARK: Lifecycle

        init(coordinator: Coordinator) {
            super.init(frame: .zero)

            directionalLayoutMargins = NSDirectionalEdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)

            let titleFont = UIFont.preferredFont(forTextStyle: .caption1)
            let titleFontDescriptor = titleFont.fontDescriptor.withSymbolicTraits(.traitBold)
                ?? titleFont.fontDescriptor
            titleLabel.font = UIFont(descriptor: titleFontDescriptor, size: titleFont.pointSize)
            titleLabel.adjustsFontForContentSizeCategory = true
            titleLabel.text = Self.title
            titleLabel.textColor = tintColor

            summaryLabel.font = .preferredFont(forTextStyle: .subheadline)
            summaryLabel.adjustsFontForContentSizeCategory = true
            summaryLabel.textColor = .label
            summaryLabel.lineBreakMode = .byTruncatingTail
            summaryLabel.numberOfLines = 1

            let messageLabels = UIStackView(arrangedSubviews: [titleLabel, summaryLabel])
            messageLabels.axis = .vertical
            messageLabels.spacing = 2
            messageLabels.isUserInteractionEnabled = false
            messageLabels.translatesAutoresizingMaskIntoConstraints = false
            openMessageButton.addSubview(messageLabels)
            NSLayoutConstraint.activate([
                messageLabels.leadingAnchor.constraint(equalTo: openMessageButton.leadingAnchor),
                messageLabels.trailingAnchor.constraint(equalTo: openMessageButton.trailingAnchor),
                messageLabels.topAnchor.constraint(equalTo: openMessageButton.topAnchor),
                messageLabels.bottomAnchor.constraint(equalTo: openMessageButton.bottomAnchor),
            ])

            openMessageButton.addTarget(
                coordinator,
                action: #selector(Coordinator.performOpenMessage),
                for: .touchUpInside,
            )
            openMessageButton.contentHorizontalAlignment = .leading
            openMessageButton.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

            showAllButton.setImage(UIImage(systemName: "chevron.right"), for: .normal)
            showAllButton.accessibilityLabel = "Show All Pinned Messages"
            showAllButton.addTarget(
                coordinator,
                action: #selector(Coordinator.performShowAllMessages),
                for: .touchUpInside,
            )

            let controls = UIStackView(arrangedSubviews: [openMessageButton, showAllButton])
            controls.alignment = .center
            controls.spacing = 8
            controls.translatesAutoresizingMaskIntoConstraints = false
            addSubview(controls)

            NSLayoutConstraint.activate([
                controls.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
                controls.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
                controls.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor),
                controls.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor),
                showAllButton.widthAnchor.constraint(equalToConstant: 44),
                showAllButton.heightAnchor.constraint(equalToConstant: 44),
            ])
        }

        @available(*, unavailable) required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        // MARK: Internal

        override func tintColorDidChange() {
            super.tintColorDidChange()
            titleLabel.textColor = tintColor
        }

        func update(summary: String) {
            guard summaryLabel.text != summary else { return }
            summaryLabel.text = summary
            openMessageButton.accessibilityLabel = "\(Self.title), \(summary)"
        }

        // MARK: Private

        private static let title = "Pinned Message"

        private let openMessageButton = UIButton(type: .custom)
        private let showAllButton = UIButton(type: .system)
        private let summaryLabel = UILabel()
        private let titleLabel = UILabel()
    }

    let summary: String
    let openMessage: () -> Void
    let showAllMessages: () -> Void

    func makeUIView(context: Context) -> BannerView {
        BannerView(coordinator: context.coordinator)
    }

    func updateUIView(_ banner: BannerView, context: Context) {
        context.coordinator.openMessage = openMessage
        context.coordinator.showAllMessages = showAllMessages
        banner.update(summary: summary)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(openMessage: openMessage, showAllMessages: showAllMessages)
    }
}
