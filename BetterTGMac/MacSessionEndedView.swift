// MacSessionEndedView.swift

import SwiftUI

// MARK: - MacSessionEndedView

struct MacSessionEndedView: View {
    let canReauthenticate: Bool
    let reauthenticate: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
                .accessibilityHidden(true)

            Text("Telegram Session Ended")
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)

            Text(
                "Your authorization for SwiftTG is no longer active. The session may have been terminated from another Telegram client or by Telegram.",
            )
            .multilineTextAlignment(.center)

            Text(TelegramLoginGuidance.smsWarning)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if canReauthenticate {
                Button("Reauthenticate") { reauthenticate() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            } else {
                ProgressView("Preparing reauthentication…")
            }
        }
        .frame(maxWidth: 520)
        .padding(40)
    }
}
