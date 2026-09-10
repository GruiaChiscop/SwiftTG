// ChatInfoMembersPreviewSection.swift

import SwiftUI

/// Inline list of members, shown for small groups (≤ 5) in place of just a count.
struct ChatInfoMembersPreviewSection: View {
    // MARK: Internal

    let info: TelegramChatInfoData

    var body: some View {
        if info.memberTotalCount > 0, info.memberTotalCount <= 5, !info.members.isEmpty {
            Section(chatVM.customChat.kind == .channel ? "Subscribers" : "Members") {
                ForEach(info.members) { member in
                    Button {
                        ChatInfoNavigation.open(member: member.id, dismiss: dismiss)
                    } label: {
                        row(member)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Private

    @Environment(ChatVM.self) private var chatVM
    @Environment(\.dismiss) private var dismiss

    private func row(_ member: TelegramChatInfoMember) -> some View {
        HStack(spacing: 12) {
            ProfileImageView(
                photo: member.photo,
                minithumbnail: member.minithumbnail,
                title: member.name,
                userId: member.placeholderId,
                fontSize: 16,
            )
            .frame(width: 36, height: 36)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(member.name)
                    .foregroundStyle(.primary)
                let details = [member.role, member.presence].compactMap(\.self)
                if !details.isEmpty {
                    Text(details.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .contentShape(Rectangle())
    }
}
