// TelegramChatNotificationTogglesRow.swift

import SwiftUI
import TDLibKit

/// The "Message Previews" and "Story Notifications" toggles for a chat's notification settings,
/// shared by `ChatInfoView` and `MacChatInfoView`. While a setting is inherited, the toggle shows
/// the effective scope value; changing it creates an explicit per-chat override.
struct TelegramChatNotificationTogglesRow: View {
    // MARK: Lifecycle

    init(
        service: any TelegramService,
        chatId: Int64,
        settings: ChatNotificationSettings,
        defaultShowPreview: Bool,
        defaultMuteStories: Bool,
        onError: @escaping (String) -> Void,
    ) {
        self.service = service
        self.chatId = chatId
        self.defaultShowPreview = defaultShowPreview
        self.defaultMuteStories = defaultMuteStories
        self.onError = onError
        _settings = State(initialValue: settings)
        _showPreview = State(initialValue: settings.useDefaultShowPreview ? defaultShowPreview : settings.showPreview)
        _storyNotifications = State(
            initialValue: !(settings.useDefaultMuteStories ? defaultMuteStories : settings.muteStories),
        )
    }

    // MARK: Internal

    var body: some View {
        Toggle("Message Previews", isOn: $showPreview)
            .onChange(of: showPreview) { _, newValue in
                guard ignoredShowPreviewChange != newValue else {
                    ignoredShowPreviewChange = nil
                    return
                }
                setShowPreview(newValue)
            }
            .disabled(isSaving)

        Toggle("Story Notifications", isOn: $storyNotifications)
            .onChange(of: storyNotifications) { _, newValue in
                guard ignoredStoryNotificationsChange != newValue else {
                    ignoredStoryNotificationsChange = nil
                    return
                }
                setStoryNotifications(newValue)
            }
            .disabled(isSaving)
    }

    // MARK: Private

    @State private var settings: ChatNotificationSettings
    @State private var showPreview: Bool
    @State private var storyNotifications: Bool
    @State private var isSaving = false
    @State private var ignoredShowPreviewChange: Bool?
    @State private var ignoredStoryNotificationsChange: Bool?

    private let service: any TelegramService
    private let chatId: Int64
    private let defaultShowPreview: Bool
    private let defaultMuteStories: Bool
    private let onError: (String) -> Void

    private func setShowPreview(_ newValue: Bool) {
        let current = settings
        let previousValue = current.useDefaultShowPreview ? defaultShowPreview : current.showPreview
        guard !isSaving else {
            ignoredShowPreviewChange = previousValue
            showPreview = previousValue
            return
        }
        isSaving = true
        Task {
            do {
                settings = try await TelegramChatActions.setShowPreview(
                    service: service,
                    chatId: chatId,
                    showPreview: newValue,
                    current: current,
                )
            } catch {
                ignoredShowPreviewChange = previousValue
                showPreview = previousValue
                onError(telegramErrorDescription(error))
            }
            isSaving = false
        }
    }

    private func setStoryNotifications(_ newValue: Bool) {
        let current = settings
        let previousMuted = current.useDefaultMuteStories ? defaultMuteStories : current.muteStories
        guard !isSaving else {
            let previousValue = !previousMuted
            ignoredStoryNotificationsChange = previousValue
            storyNotifications = previousValue
            return
        }
        isSaving = true
        Task {
            do {
                settings = try await TelegramChatActions.setMuteStories(
                    service: service,
                    chatId: chatId,
                    muteStories: !newValue,
                    current: current,
                )
            } catch {
                let previousValue = !previousMuted
                ignoredStoryNotificationsChange = previousValue
                storyNotifications = previousValue
                onError(telegramErrorDescription(error))
            }
            isSaving = false
        }
    }
}
