// AccessibleBroadcastPickerView.swift

import ReplayKit
import UIKit

// MARK: - AccessibleBroadcastPickerView

/// Gives ReplayKit's otherwise opaque picker a full-size hit target and explicit VoiceOver button
/// semantics. Telegram-iOS likewise stretches a nearly-transparent system picker over its custom
/// share-screen control.
final class AccessibleBroadcastPickerView: UIView {
    // MARK: Lifecycle

    init(isEnabled: Bool, label: String) {
        super.init(frame: .zero)

        picker.preferredExtension = Self.broadcastExtensionIdentifier
        picker.showsMicrophoneButton = false
        picker.alpha = 0.02
        picker.translatesAutoresizingMaskIntoConstraints = false
        addSubview(picker)
        NSLayoutConstraint.activate([
            picker.leadingAnchor.constraint(equalTo: leadingAnchor),
            picker.trailingAnchor.constraint(equalTo: trailingAnchor),
            picker.topAnchor.constraint(equalTo: topAnchor),
            picker.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        activationButton.translatesAutoresizingMaskIntoConstraints = false
        activationButton.isAccessibilityElement = false
        activationButton.addTarget(self, action: #selector(didPressActivationButton), for: .touchUpInside)
        addSubview(activationButton)
        NSLayoutConstraint.activate([
            activationButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            activationButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            activationButton.topAnchor.constraint(equalTo: topAnchor),
            activationButton.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        isAccessibilityElement = true
        accessibilityIdentifier = "call.shareScreen"
        update(isEnabled: isEnabled, label: label)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Internal

    override func accessibilityActivate() -> Bool {
        triggerPicker()
    }

    func update(isEnabled: Bool, label: String) {
        self.isEnabled = isEnabled
        picker.isUserInteractionEnabled = isEnabled
        activationButton.isEnabled = isEnabled
        accessibilityLabel = label
        accessibilityTraits = isEnabled ? [.button] : [.button, .notEnabled]
    }

    // MARK: Private

    private static let broadcastExtensionIdentifier = "com.gruiachiscop.BetterTG.BroadcastUpload"

    private let picker = RPSystemBroadcastPickerView()
    private let activationButton = UIButton(type: .custom)
    private var isEnabled = true

    @objc private func didPressActivationButton() {
        _ = triggerPicker()
    }

    private func triggerPicker() -> Bool {
        guard isEnabled else { return false }
        picker.layoutIfNeeded()
        guard let button = picker.firstDescendant(of: UIButton.self) else { return false }
        button.sendActions(for: .touchUpInside)
        return true
    }
}

// MARK: - UIView helpers

private extension UIView {
    func firstDescendant<View: UIView>(of _: View.Type) -> View? {
        if let view = self as? View {
            return view
        }
        for subview in subviews {
            if let view = subview.firstDescendant(of: View.self) {
                return view
            }
        }
        return nil
    }
}
