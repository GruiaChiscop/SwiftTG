// TelegramChatNotificationTogglesRow.swift

import SwiftUI
import TDLibKit

/// The "Message Previews" and "Story Notifications" toggles for a chat's notification settings,
/// shared by `ChatInfoView` and `MacChatInfoView`. Snapshots the settings at init and mutates
/// locally on each change, mirroring `TelegramChatSoundRow`.
struct TelegramChatNotificationTogglesRow: View {
    // MARK: Lifecycle

    init(service: any TelegramService, chatId: Int64, settings: ChatNotificationSettings) {
        self.service = service
        self.chatId = chatId
        _settings = State(initialValue: settings)
        _showPreview = State(initialValue: settings.showPreview)
        _storyNotifications = State(initialValue: !settings.muteStories)
    }

    // MARK: Internal

    var body: some View {
        Toggle("Message Previews", isOn: $showPreview)
            .onChange(of: showPreview) { _, newValue in
                Task {
                    settings = await TelegramChatActions.setShowPreview(
                        service: service,
                        chatId: chatId,
                        showPreview: newValue,
                        current: settings,
                    )
                }
            }

        Toggle("Story Notifications", isOn: $storyNotifications)
            .onChange(of: storyNotifications) { _, newValue in
                Task {
                    settings = await TelegramChatActions.setMuteStories(
                        service: service,
                        chatId: chatId,
                        muteStories: !newValue,
                        current: settings,
                    )
                }
            }
    }

    // MARK: Private

    private let service: any TelegramService
    private let chatId: Int64

    @State private var settings: ChatNotificationSettings
    @State private var showPreview: Bool
    @State private var storyNotifications: Bool
}
