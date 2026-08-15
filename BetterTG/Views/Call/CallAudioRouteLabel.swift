// CallAudioRouteLabel.swift

import SwiftUI

// MARK: - CallAudioRouteLabel

struct CallAudioRouteLabel: View {
    let systemImage: String
    let title: String
    let isActive: Bool

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.title2)
                .frame(width: 64, height: 64)
                .background(isActive ? .white : .white.opacity(0.16), in: .circle)
                .foregroundStyle(isActive ? .black : .white)
                .accessibilityHidden(true)

            Text(title)
                .font(.callout)
                .foregroundStyle(.primary)
        }
    }
}
