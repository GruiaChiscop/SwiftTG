// ChatInfoNotificationsSection.swift

import SwiftUI

/// Notification sound and preview/story toggles. Muting itself is a header quick-action, matching
/// Telegram-iOS - see `ChatInfoHeaderActionsView`/`ChatInfoView.isMuted(_:)`.
struct ChatInfoNotificationsSection: View {
    // MARK: Internal

    let defaultShowPreview: Bool
    let defaultMuteStories: Bool
    let onError: (String) -> Void

    var body: some View {
        Section("Notifications") {
            TelegramChatSoundRow(service: chatVM.service, chatId: chat.id, settings: chat.notificationSettings)

            TelegramChatNotificationTogglesRow(
                service: chatVM.service,
                chatId: chat.id,
                settings: chat.notificationSettings,
                defaultShowPreview: defaultShowPreview,
                defaultMuteStories: defaultMuteStories,
                onError: onError,
            )
        }
    }

    // MARK: Private

    @Environment(ChatVM.self) private var chatVM

    private var chat: CustomChat { chatVM.customChat }
}
