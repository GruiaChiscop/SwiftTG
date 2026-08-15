// TelegramCallBar.swift

import SwiftUI

// MARK: - TelegramCallBar

struct TelegramCallBar: View {
    // MARK: Internal

    var body: some View {
        if session.shouldShowMinimizedCallBar {
            Button(action: session.restoreCallView) {
                HStack(spacing: 12) {
                    Image(systemName: "phone.fill")
                        .foregroundStyle(.green)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ongoing Call")
                            .font(.subheadline.bold())

                        CallStatusView(
                            call: session.activeCall,
                            connectedAt: session.connectedAt,
                            engineState: session.engineState,
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "chevron.up")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .background(.bar)
        }
    }

    // MARK: Private

    @State private var session = TelegramCallSession.shared
}
