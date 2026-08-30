// TelegramLiveLocationBar.swift

import SwiftUI

/// Global "you're sharing your live location" indicator, following the same
/// self-hiding-when-empty pattern as `TelegramAudioPlayerBar` - shown from any chat, not just the
/// one a share was started in, since more than one can be active across different chats at once.
/// Each row is two distinct controls: the body opens the chat, a separate "Stop" button ends the
/// share. (`MessageLocationView` carries its own Stop button on the live-location bubble too.)
struct TelegramLiveLocationBar: View {
    // MARK: Internal

    var body: some View {
        if !manager.activeShares.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(sortedShares.enumerated()), id: \.element.id) { index, share in
                    if index > 0 {
                        Divider()
                    }
                    row(for: share)
                }
            }
            .background(.bar)
            .accessibilityElement(children: .contain)
        }
    }

    // MARK: Private

    @State private var manager = TelegramLiveLocationManager.shared

    private var sortedShares: [TelegramLiveShare] {
        manager.activeShares.values.sorted { $0.expiresAt < $1.expiresAt }
    }

    private func row(for share: TelegramLiveShare) -> some View {
        HStack(spacing: 12) {
            Button {
                open(share)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "location.fill.viewfinder")
                        .foregroundStyle(Color.accentColor)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sharing Live Location")
                            .font(.subheadline.weight(.semibold))
                        Text(share.chatTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if share.isIndefinite {
                        Text("Indefinitely")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(share.expiresAt, style: .timer)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                share.isIndefinite
                    ? "Sharing live location indefinitely in \(share.chatTitle)"
                    : "Sharing live location in \(share.chatTitle)",
            )

            Button("Stop") {
                Task { await manager.stop(messageId: share.messageId) }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.red)
            .accessibilityLabel("Stop sharing live location in \(share.chatTitle)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func open(_ share: TelegramLiveShare) {
        Task {
            guard let chat = await RootVM.shared.getCustomChat(from: share.chatId) else { return }
            RootVM.shared.navigate(to: .customChat(chat))
        }
    }
}
