// CallBackground.swift

import SwiftUI

// MARK: - CallBackground

struct CallBackground: View {
    let userId: Int64?

    var body: some View {
        ZStack {
            Color.black
            LinearGradient(
                colors: [
                    Color(telegramAvatarId: userId ?? 0).opacity(0.72),
                    Color.black.opacity(0.92),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing,
            )
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
