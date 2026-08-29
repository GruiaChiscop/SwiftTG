// CallControlButton.swift

import SwiftUI

// MARK: - CallControlButton

struct CallControlButton: View {
    // MARK: Internal

    let systemImage: String
    let label: String
    var isActive = false
    var isDestructive = false
    var isEnabled = true
    var showsLabel = true
    let action: () -> Void

    var body: some View {
        Group {
            if showsLabel {
                Button(action: action) {
                    VStack(spacing: 8) {
                        Image(systemName: systemImage)
                            .font(.title2)
                            .frame(width: 64, height: 64)
                            .background(controlBackground, in: .circle)
                            .foregroundStyle(controlForeground)
                            .accessibilityHidden(true)

                        Text(label)
                            .font(.callout)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
            } else {
                Button(label, systemImage: systemImage, action: action)
                    .labelStyle(.iconOnly)
                    .font(.title2)
                    .frame(width: 56, height: 56)
                    .background(controlBackground, in: .circle)
                    .foregroundStyle(controlForeground)
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
        .accessibilityAddTraits(isActive && !isDestructive ? .isSelected : [])
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
