// ChatInfoAutoDeleteSection.swift

import SwiftUI

/// Message auto-delete timer. A menu of Telegram's preset stops (Off / 1 day / 1 week / 1 month)
/// when the current user can change it, a read-only row when a timer is set but they can't.
/// Failures are surfaced through `onError` (`ChatInfoView` owns the alert).
struct ChatInfoAutoDeleteSection: View {
    // MARK: Internal

    let info: TelegramChatInfoData
    let onError: (String) -> Void

    var body: some View {
        if canEdit || autoDeleteSeconds > 0 {
            Section {
                if canEdit {
                    Menu {
                        ForEach(Self.presets, id: \.seconds) { preset in
                            Button {
                                setAutoDelete(preset.seconds)
                            } label: {
                                if autoDeleteSeconds == preset.seconds {
                                    Label(preset.title, systemImage: "checkmark")
                                } else {
                                    Text(preset.title)
                                }
                            }
                        }
                    } label: {
                        rowLabel
                    }
                } else {
                    rowLabel
                }
            } footer: {
                Text("Automatically delete messages sent in this chat after a certain period of time.")
            }
        }
    }

    // MARK: Private

    /// Telegram-iOS's `PeerAutoremoveSetupScreen` preset stops: Off, 1 day, 1 week, 31 days.
    private static let presets: [(title: String, seconds: Int)] = [
        ("Off", 0),
        ("1 Day", 86_400),
        ("1 Week", 604_800),
        ("1 Month", 2_678_400),
    ]

    @Environment(ChatVM.self) private var chatVM
    @State private var autoDeleteOverride: Int?

    private var chat: CustomChat { chatVM.customChat }

    private var autoDeleteSeconds: Int {
        autoDeleteOverride ?? info.messageAutoDeleteTime
    }

    private var canEdit: Bool {
        guard !chat.isSavedMessages else { return false }
        switch chat.kind {
        case .privateChat, .bot:
            return true
        case .group, .channel:
            return info.canChangeInfo
        }
    }

    private var rowLabel: some View {
        LabeledContent {
            Text(Self.label(autoDeleteSeconds))
        } label: {
            Label("Auto-Delete Messages", systemImage: "timer")
        }
        .foregroundStyle(.primary)
        .contentShape(Rectangle())
    }

    private static func label(_ seconds: Int) -> String {
        switch seconds {
        case 0: "Off"
        case 86_400: "1 day"
        case 604_800: "1 week"
        case 2_678_400: "1 month"
        case let value where value % 86_400 == 0: "\(value / 86_400) days"
        default: "\(max(1, seconds / 3_600)) hours"
        }
    }

    private func setAutoDelete(_ seconds: Int) {
        let previous = autoDeleteSeconds
        guard seconds != previous else { return }
        autoDeleteOverride = seconds
        let service = chatVM.service
        let chatId = chat.id
        Task {
            do {
                _ = try await service.setChatMessageAutoDeleteTime(
                    chatId: chatId,
                    messageAutoDeleteTime: seconds,
                )
            } catch {
                autoDeleteOverride = previous
                onError(telegramErrorDescription(error))
            }
        }
    }
}
