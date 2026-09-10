// ChatInfoSharedContentSection.swift

import SwiftUI

/// Shared media, scheduled messages, and groups-in-common entry points. Presentation is owned by
/// `ChatInfoView` (sheets don't fire reliably from inside a `List` row); this is just the rows.
struct ChatInfoSharedContentSection: View {
    let info: TelegramChatInfoData
    let onOpenSharedMedia: () -> Void
    let onOpenScheduledMessages: () -> Void
    let onOpenCommonGroups: () -> Void

    var body: some View {
        Section {
            Button(action: onOpenSharedMedia) {
                Label("Shared Media", systemImage: "photo.on.rectangle")
            }

            Button(action: onOpenScheduledMessages) {
                Label("Scheduled Messages", systemImage: "clock")
            }

            if let commonGroupCount = info.commonGroupCount,
               commonGroupCount > 0,
               info.commonGroupsUserId != nil
            {
                Button(action: onOpenCommonGroups) {
                    LabeledContent("Groups in common", value: commonGroupCount.formatted())
                        .foregroundStyle(.primary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
