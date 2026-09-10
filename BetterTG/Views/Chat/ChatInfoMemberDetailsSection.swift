// ChatInfoMemberDetailsSection.swift

import SwiftUI

/// Member / administrator / restricted / banned counts. Tapping one asks `ChatInfoView` to push
/// `ChatInfoMembersView` for that filter.
struct ChatInfoMemberDetailsSection: View {
    // MARK: Internal

    let info: TelegramChatInfoData
    let onOpenMembers: (TelegramChatInfoMemberFilter) -> Void

    var body: some View {
        if info.memberCount != nil
            || info.administratorCount != nil
            || info.restrictedCount != nil
            || info.bannedCount != nil
        {
            Section {
                if let memberCount = info.memberCount {
                    let title = chatVM.customChat.kind == .channel ? "Subscribers" : "Members"
                    if info.canBrowseMembers {
                        countRow(title, count: memberCount, filter: .members)
                    } else {
                        LabeledContent(title, value: memberCount.formatted())
                    }
                }

                if let administratorCount = info.administratorCount, administratorCount > 0 {
                    countRow("Administrators", count: administratorCount, filter: .administrators)
                }

                if let restrictedCount = info.restrictedCount, restrictedCount > 0 {
                    countRow("Restricted", count: restrictedCount, filter: .restricted)
                }

                if let bannedCount = info.bannedCount, bannedCount > 0 {
                    countRow("Banned", count: bannedCount, filter: .banned)
                }
            }
        }
    }

    // MARK: Private

    @Environment(ChatVM.self) private var chatVM

    private func countRow(_ title: String, count: Int, filter: TelegramChatInfoMemberFilter) -> some View {
        Button {
            onOpenMembers(filter)
        } label: {
            LabeledContent(title, value: count.formatted())
                .foregroundStyle(.primary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
