// CallAudioRouteLabel.swift

import SwiftUI

// MARK: - CallAudioRouteLabel

struct CallAudioRouteLabel: View {
    let systemImage: String
    let title: String
    let isActive: Bool
    var showsLabel = true

    var body: some View {
        if showsLabel {
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
        } else {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .font(.title2)
                .frame(width: 56, height: 56)
                .background(isActive ? .white : .white.opacity(0.16), in: .circle)
                .foregroundStyle(isActive ? .black : .white)
        }
    }
}
