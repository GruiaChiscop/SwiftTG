// CallControlButton.swift

import SwiftUI

// MARK: - CallControlButton

struct CallControlButton: View {
    // MARK: Internal

    let systemImage: String
    let label: String
    var isActive = false
    var isDestructive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .frame(width: 64, height: 64)
                    .background(controlBackground, in: .circle)
                    .foregroundStyle(controlForeground)

                Text(label)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .buttonStyle(.plain)
        .accessibilityValue(isDestructive ? "" : (isActive ? "On" : "Off"))
    }

    // MARK: Private

    private var controlBackground: Color {
        if isDestructive {
            return .red
        }
        return isActive ? .white : .white.opacity(0.16)
    }

    private var controlForeground: Color {
        if isDestructive {
            return .white
        }
        return isActive ? .black : .white
    }
}
