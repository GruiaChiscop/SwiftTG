// CallFeedbackSuccessView.swift

import SwiftUI

// MARK: - CallFeedbackSuccessView

struct CallFeedbackSuccessView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "star.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.yellow)

            Text("Thanks for\nyour feedback")
                .font(.headline)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .background(.regularMaterial, in: .rect(cornerRadius: 20))
        .shadow(color: .black.opacity(0.2), radius: 20, y: 8)
        // The transient visual must not trigger a VoiceOver layout refresh; RootView posts the
        // matching Telegram announcement explicitly after the rating sheet has disappeared.
        .accessibilityHidden(true)
    }
}
