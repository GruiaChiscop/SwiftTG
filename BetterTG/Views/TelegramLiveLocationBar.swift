// TelegramLiveLocationBar.swift

import SwiftUI

/// Global "you're sharing your live location" indicator, following the same
/// self-hiding-when-empty pattern as `TelegramAudioPlayerBar` - shown from any chat, not just the
/// one a share was started in, since more than one can be active across different chats at once.
/// The only way to stop a share: no context-menu entry, per explicit feedback that one would be
/// too easy to miss for something actively running in the background.
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
            Image(systemName: "location.fill.viewfinder")
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)

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

            Button("Stop", systemImage: "xmark.circle.fill") {
                Task { await manager.stop(messageId: share.messageId) }
            }
            .labelStyle(.iconOnly)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            share.isIndefinite
                ? "Sharing live location indefinitely in \(share.chatTitle)"
                : "Sharing live location in \(share.chatTitle)",
        )
        .accessibilityAction(named: "Open Chat") { open(share) }
        .accessibilityAction(named: "Stop Sharing") {
            Task { await manager.stop(messageId: share.messageId) }
        }
        .onTapGesture { open(share) }
    }

    private func open(_ share: TelegramLiveShare) {
        Task {
            guard let chat = await RootVM.shared.getCustomChat(from: share.chatId) else { return }
            RootVM.shared.navigate(to: .customChat(chat))
        }
    }
}
