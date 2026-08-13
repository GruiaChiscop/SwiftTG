// TelegramUnconfirmedSessionBannerView.swift

import SwiftUI
@preconcurrency import TDLibKit

// MARK: - TelegramUnconfirmedSessionBannerView

/// Shown when TDLib reports a new login it hasn't confirmed yet (`updateUnconfirmedSession`) -
/// mirrors Telegram-iOS/Unigram's "was this you?" prompt. Purely presentational: the owning view
/// (`RootView` on iOS, `MacRootView` on macOS) holds the actual `UnconfirmedSession` state and
/// performs the confirm/deny TDLib calls, since it needs to keep working (to show a follow-up
/// notice on deny) after this view itself is removed from the hierarchy.
///
/// Only ever shown for `.sessionTypeDevice` - a connected business bot's confirmation
/// (`.sessionTypeConnectedBot`) uses different TDLib calls entirely
/// (`confirmBusinessConnectedBot`/`deleteBusinessConnectedBot`) and isn't wired up here.
struct TelegramUnconfirmedSessionBannerView: View {
    let session: UnconfirmedSession
    let isProcessing: Bool
    let onConfirm: () -> Void
    let onDeny: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("New Login", systemImage: "exclamationmark.shield.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)

            Text("\(session.deviceModel), \(session.location). Was this you?")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Button("No", role: .destructive, action: onDeny)
                    .buttonStyle(.bordered)
                Spacer()
                Button("Yes, It Was Me", action: onConfirm)
                    .buttonStyle(.borderedProminent)
            }
        }
        .disabled(isProcessing)
        .padding(12)
        .background(.bar, in: RoundedRectangle(cornerRadius: 14))
        .shadow(radius: 8, y: 2)
        .padding(.horizontal, 8)
        .accessibilityElement(children: .contain)
        .onAppear {
            // `.announcement`, not `.screenChanged` - consistent with the in-app message banner:
            // reads the prompt aloud without moving focus. Safe here too since, unlike the message
            // banner, this one doesn't auto-dismiss - it stays on screen until answered, so the
            // user will reach it on their own even if the announcement is missed.
            AccessibilityNotification.Announcement(
                "New login attempt. \(session.deviceModel), \(session.location). Was this you?",
            )
            .post()
        }
    }
}
