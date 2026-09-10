// ChatInfoNotificationsSection.swift

import SwiftUI

/// Mute toggle, notification sound, and preview/story toggles. The mute-duration popover is
/// owned by `ChatInfoView` (popovers don't fire reliably from inside a `List` row).
struct ChatInfoNotificationsSection: View {
    let isMuted: Bool
    let onMuteButtonTapped: () -> Void

    var body: some View {
        Section("Notifications") {
            Button {
                onMuteButtonTapped()
            } label: {
                Text(isMuted ? "Unmute" : "Mute")
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            TelegramChatSoundRow(service: chatVM.service, chatId: chat.id, settings: chat.notificationSettings)

            TelegramChatNotificationTogglesRow(
                service: chatVM.service,
                chatId: chat.id,
                settings: chat.notificationSettings,
            )
        }
    }

    // MARK: Private

    @Environment(ChatVM.self) private var chatVM

    private var chat: CustomChat { chatVM.customChat }
}
