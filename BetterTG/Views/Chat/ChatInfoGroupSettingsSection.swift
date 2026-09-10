// ChatInfoGroupSettingsSection.swift

import SwiftUI

/// Read-only group/channel settings: linked chat, slow mode, sign messages, reactions, hidden
/// members, restricted saving.
struct ChatInfoGroupSettingsSection: View {
    // MARK: Internal

    let info: TelegramChatInfoData

    var body: some View {
        if showsLinkedChat || showsSlowMode || showsSignMessages || showsProtectedContent
            || showsHiddenMembers || showsReactions
        {
            Section {
                if showsLinkedChat {
                    Button {
                        ChatInfoNavigation.open(chatId: info.linkedChatId, dismiss: dismiss)
                    } label: {
                        LabeledContent(
                            isChannel ? "Discussion Group" : "Linked Channel",
                            value: info.linkedChatTitle ?? "Open",
                        )
                        .foregroundStyle(.primary)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if showsSlowMode {
                    LabeledContent("Slow Mode", value: telegramSlowModeDescription(info.slowModeDelay))
                }
                if showsSignMessages {
                    LabeledContent("Sign Messages", value: info.signMessages ? "On" : "Off")
                }
                if showsReactions, let reactionsSummary = info.reactionsSummary {
                    LabeledContent("Reactions", value: reactionsSummary)
                }
                if showsHiddenMembers {
                    LabeledContent("Members", value: "Hidden")
                }
                if showsProtectedContent {
                    LabeledContent("Saving Content", value: "Restricted")
                }
            }
        }
    }

    // MARK: Private

    @Environment(ChatVM.self) private var chatVM
    @Environment(\.dismiss) private var dismiss

    private var kind: CustomChat.ChatKind { chatVM.customChat.kind }
    private var isChannel: Bool { kind == .channel }
    private var isCommunity: Bool { kind == .group || kind == .channel }

    private var showsLinkedChat: Bool { isCommunity && info.linkedChatId != 0 }
    private var showsSlowMode: Bool { kind == .group && info.slowModeDelay > 0 }
    private var showsSignMessages: Bool { isChannel && info.canChangeInfo }
    private var showsHiddenMembers: Bool { isCommunity && info.canChangeInfo && info.hasHiddenMembers }
    private var showsReactions: Bool { isCommunity && info.reactionsSummary != nil }
    private var showsProtectedContent: Bool { isCommunity && info.hasProtectedContent }
}
