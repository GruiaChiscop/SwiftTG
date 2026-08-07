// TelegramChatNotificationSound.swift

import SwiftUI
@preconcurrency import TDLibKit

// MARK: - TelegramChatSoundRow

/// A single "Sound" row for a specific chat's notification settings - reuses the same picker
/// (Default/Off/saved cloud sounds/upload) already built for the per-scope screens, so a chat can
/// either inherit its scope's sound or override it individually, matching Telegram's own per-chat
/// notification options.
struct TelegramChatSoundRow: View {
    // MARK: Lifecycle

    init(service: any TelegramService, chatId: Int64, settings: ChatNotificationSettings) {
        self.service = service
        self.chatId = chatId
        _settings = State(initialValue: settings)
    }

    // MARK: Internal

    let service: any TelegramService
    let chatId: Int64

    var body: some View {
        NavigationLink {
            TelegramNotificationSoundPickerView(service: service, selectedSoundId: pickerSoundId) { newSoundId in
                save(newSoundId)
            }
        } label: {
            LabeledContent("Sound", value: soundDisplayName)
        }
        .task(id: settings.soundId) {
            guard !settings.useDefaultSound, settings.soundId.rawValue > 0 else {
                soundTitle = nil
                return
            }
            soundTitle = try? await service.getSavedNotificationSound(notificationSoundId: settings.soundId).title
        }
    }

    // MARK: Private

    @State private var settings: ChatNotificationSettings
    @State private var soundTitle: String?

    /// The picker treats "Default" as a `-1` pseudo-id (same convention the scope screens use);
    /// only this row interprets it as `useDefaultSound` rather than a literal TDLib sound id.
    private var pickerSoundId: TdInt64 {
        settings.useDefaultSound ? -1 : settings.soundId
    }

    private var soundDisplayName: String {
        if settings.useDefaultSound { return "Default" }
        if settings.soundId.rawValue <= 0 { return "Off" }
        return soundTitle ?? "…"
    }

    private func save(_ newSoundId: TdInt64) {
        let useDefault = newSoundId.rawValue <= -1
        settings = ChatNotificationSettings(
            disableMentionNotifications: settings.disableMentionNotifications,
            disablePinnedMessageNotifications: settings.disablePinnedMessageNotifications,
            muteFor: settings.muteFor,
            muteStories: settings.muteStories,
            showPreview: settings.showPreview,
            showStoryPoster: settings.showStoryPoster,
            soundId: useDefault ? settings.soundId : newSoundId,
            storySoundId: settings.storySoundId,
            useDefaultDisableMentionNotifications: settings.useDefaultDisableMentionNotifications,
            useDefaultDisablePinnedMessageNotifications: settings.useDefaultDisablePinnedMessageNotifications,
            useDefaultMuteFor: settings.useDefaultMuteFor,
            useDefaultMuteStories: settings.useDefaultMuteStories,
            useDefaultShowPreview: settings.useDefaultShowPreview,
            useDefaultShowStoryPoster: settings.useDefaultShowStoryPoster,
            useDefaultSound: useDefault,
            useDefaultStorySound: settings.useDefaultStorySound,
        )
        Task {
            await TelegramChatActions.setSoundId(
                service: service,
                chatId: chatId,
                soundId: newSoundId,
                useDefault: useDefault,
                current: settings,
            )
        }
    }
}
