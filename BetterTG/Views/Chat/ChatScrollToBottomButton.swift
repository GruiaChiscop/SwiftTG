// ChatScrollToBottomButton.swift

import UIKit

// MARK: - ChatScrollToBottomButton

@MainActor final class ChatScrollToBottomButton: UIButton {
    // MARK: Lifecycle

    override init(frame: CGRect) {
        super.init(frame: frame)

        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: "chevron.down")
        configuration.baseForegroundColor = .tintColor
        configuration.contentInsets = .zero
        self.configuration = configuration

        backgroundColor = .black
        layer.cornerRadius = 24
        layer.borderColor = UIColor.tintColor.cgColor
        layer.borderWidth = 1
        clipsToBounds = false

        accessibilityLabel = "Scroll to bottom"

        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        badgeLabel.backgroundColor = .tintColor
        badgeLabel.font = .preferredFont(forTextStyle: .caption2)
        badgeLabel.textColor = .white
        badgeLabel.textAlignment = .center
        badgeLabel.adjustsFontSizeToFitWidth = true
        badgeLabel.minimumScaleFactor = 0.5
        badgeLabel.layer.cornerRadius = 8
        badgeLabel.clipsToBounds = true
        badgeLabel.isAccessibilityElement = false
        addSubview(badgeLabel)
        NSLayoutConstraint.activate([
            badgeLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            badgeLabel.centerYAnchor.constraint(equalTo: topAnchor),
            badgeLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 16),
            badgeLabel.heightAnchor.constraint(equalToConstant: 16),
        ])

        alpha = 0
        isHidden = true
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Internal

    var onAccessibilityFocus: (() -> Void)?

    override func accessibilityElementDidBecomeFocused() {
        super.accessibilityElementDidBecomeFocused()
        onAccessibilityFocus?()
    }

    func update(unreadCount: Int) {
        badgeLabel.text = unreadCount > 0 ? "\(unreadCount)" : nil
        badgeLabel.isHidden = unreadCount == 0
    }

    func setVisible(_ visible: Bool, animated: Bool) {
        guard visible != isVisible else { return }
        isVisible = visible
        layer.removeAllAnimations()

        if visible {
            isHidden = false
        }

        let changes = {
            self.alpha = visible ? 1 : 0
            self.transform = visible ? .identity : CGAffineTransform(scaleX: 0.85, y: 0.85)
        }
        let completion = { [weak self] in
            guard let self, !isVisible else { return }
            isHidden = true
        }

        if animated {
            UIView.animate(withDuration: 0.2, animations: changes) { _ in completion() }
        } else {
            changes()
            completion()
        }
    }

    // MARK: Private

    private let badgeLabel = UILabel()
    private var isVisible = false
}
