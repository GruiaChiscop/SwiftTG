// TelegramCallBar.swift

import SwiftUI
import TDLibKit

// MARK: - TelegramCallBar

struct TelegramCallBar: View {
    // MARK: Internal

    var body: some View {
        if session.shouldShowMinimizedCallBar {
            Button(action: session.restoreCallView) {
                HStack(spacing: 12) {
                    CallPeerAvatar(
                        user: user,
                        fallbackTitle: displayName,
                        userId: session.activeCall?.userId,
                    )
                    .frame(width: 36, height: 36)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(displayName)
                            .font(.subheadline.bold())
                            .lineLimit(1)

                        Group {
                            if session.isConferenceCall {
                                Text(session.conferenceConnectionStatus ?? "Group Call")
                            } else {
                                CallStatusView(
                                    call: session.activeCall,
                                    connectedAt: session.connectedAt,
                                    engineState: session.engineState,
                                    signalBars: session.signalBars,
                                )
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "phone.fill")
                        .foregroundStyle(.green)
                        .accessibilityHidden(true)

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
            .task(id: session.activeCall?.userId) {
                await loadUser()
            }
        }
    }

    // MARK: Private

    @State private var session = TelegramCallSession.shared
    @State private var user: User?

    private var displayName: String {
        if session.isConferenceCall {
            return "Group Call"
        }
        guard let user else { return "Telegram" }
        let name = [user.firstName, user.lastName].filter { !$0.isEmpty }.joined(separator: " ")
        return name.isEmpty ? "Telegram" : name
    }

    private func loadUser() async {
        guard let userId = session.activeCall?.userId, user?.id != userId else { return }
        user = nil
        guard let loadedUser = try? await TDLib.shared.service.getUser(userId: userId) else { return }
        guard !Task.isCancelled, session.activeCall?.userId == userId else { return }
        user = loadedUser
    }
}
