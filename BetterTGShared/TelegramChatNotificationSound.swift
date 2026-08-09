// TelegramChatNotificationSound.swift

import SwiftUI
@preconcurrency import TDLibKit

// MARK: - TelegramChatSoundRow

/// A single "Sound" row for a specific chat's (or forum topic's) notification settings - reuses
/// the same picker (Default/Off/saved cloud sounds/upload) already built for the per-scope
/// screens, so a chat/topic can either inherit its parent's sound or override it individually,
/// matching Telegram's own per-chat *and* per-topic notification options (Telegram-iOS reuses its
/// "Exceptions" sound screen for both, scoped by an optional thread id - same idea here).
struct TelegramChatSoundRow: View {
    // MARK: Lifecycle

    /// Whole-chat notification settings.
    init(service: any TelegramService, chatId: Int64, settings: ChatNotificationSettings) {
        self.service = service
        _settings = State(initialValue: settings)
        self.persist = { newSoundId, useDefault, current in
            await TelegramChatActions.setSoundId(
                service: service,
                chatId: chatId,
                soundId: newSoundId,
                useDefault: useDefault,
                current: current,
            )
        }
    }

    /// A single forum topic's notification settings - `TelegramNotificationSoundCache` isn't
    /// updated here the way the chat-level init does, since that cache exists only to let the
    /// (TDLib-less) Notification Service Extension resolve a chat's sound from a bare push
    /// payload, which never carries topic information for it to key off - see
    /// `MacSessionModel+Notifications.swift`'s topic-sound resolution for where a topic override
    /// actually gets honored (Mac only, where local notifications are built with live TDLib data).
    init(service: any TelegramService, chatId: Int64, forumTopicId: Int, settings: ChatNotificationSettings) {
        self.service = service
        _settings = State(initialValue: settings)
        self.persist = { newSoundId, useDefault, current in
            await TelegramForumTopicSending.setSoundId(
                service: service,
                chatId: chatId,
                forumTopicId: forumTopicId,
                soundId: newSoundId,
                useDefault: useDefault,
                current: current,
            )
        }
    }

    // MARK: Internal

    let service: any TelegramService
    let persist: (_ newSoundId: TdInt64, _ useDefault: Bool, _ current: ChatNotificationSettings) async -> Void

    var body: some View {
        #if os(iOS)
            NavigationLink {
                TelegramNotificationSoundPickerView(service: service, selectedSoundId: pickerSoundId) { newSoundId in
                    save(newSoundId)
                }
            } label: {
                LabeledContent("Sound", value: soundDisplayName)
            }
            .task(id: settings.soundId) {
                await loadSoundTitleIfNeeded()
            }
        #else
            Button {
                showsSoundPicker = true
            } label: {
                LabeledContent("Sound", value: soundDisplayName)
                    .foregroundStyle(.primary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .task(id: settings.soundId) {
                await loadSoundTitleIfNeeded()
            }
            .sheet(isPresented: $showsSoundPicker) {
                TelegramNotificationSoundPickerSheet(service: service, selectedSoundId: pickerSoundId) { newSoundId in
                    save(newSoundId)
                }
            }
        #endif
    }

    // MARK: Private

    @State private var settings: ChatNotificationSettings
    #if os(macOS)
    @State private var showsSoundPicker = false
    #endif
    @State private var soundTitle: String?

    /// The picker treats "Default" as a `-1` pseudo-id (same convention the scope screens use);
    /// only this row interprets it as `useDefaultSound` rather than a literal TDLib sound id.
    private var pickerSoundId: TdInt64 {
        settings.useDefaultSound ? -1 : settings.soundId
    }

    private var soundDisplayName: String {
        if settings.useDefaultSound {
            return "Default"
        }
        if settings.soundId.rawValue <= 0 {
            return "Off"
        }
        return soundTitle ?? "…"
    }

    private func loadSoundTitleIfNeeded() async {
        guard !settings.useDefaultSound, settings.soundId.rawValue > 0 else {
            soundTitle = nil
            return
        }
        soundTitle = try? await service.getSavedNotificationSound(notificationSoundId: settings.soundId).title
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
            await persist(newSoundId, useDefault, settings)
        }
    }
}
