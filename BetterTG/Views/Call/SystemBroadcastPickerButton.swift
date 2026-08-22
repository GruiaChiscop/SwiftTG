// SystemBroadcastPickerButton.swift

import SwiftUI

// MARK: - SystemBroadcastPickerButton

struct SystemBroadcastPickerButton: UIViewRepresentable {
    let isEnabled: Bool
    let label: String

    func makeUIView(context _: Context) -> AccessibleBroadcastPickerView {
        AccessibleBroadcastPickerView(isEnabled: isEnabled, label: label)
    }

    func updateUIView(_ uiView: AccessibleBroadcastPickerView, context _: Context) {
        uiView.update(isEnabled: isEnabled, label: label)
    }
}
