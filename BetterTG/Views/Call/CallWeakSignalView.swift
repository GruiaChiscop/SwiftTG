// CallWeakSignalView.swift

import SwiftUI

// MARK: - CallWeakSignalView

struct CallWeakSignalView: View {
    // MARK: Internal

    let isVisible: Bool

    var body: some View {
        Group {
            if isVisible {
                CallNoticeLabel(
                    title: "Weak network signal",
                    systemImage: "wifi.exclamationmark",
                )
            }
        }
        .onChange(of: isVisible, announceWeakSignal)
    }

    // MARK: Private

    private func announceWeakSignal(previous _: Bool, current: Bool) {
        guard current else { return }
        AccessibilityNotification.Announcement("Weak network signal").post()
    }
}
