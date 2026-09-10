// ChatInfoIdentitySection.swift

import SwiftUI

/// The header block: avatar, title, trust badges, status/member-count line, and the
/// call / video / search action row. Permission alerts are owned by `ChatInfoView`.
struct ChatInfoIdentitySection: View {
    // MARK: Internal

    let info: TelegramChatInfoData?
    let onMicrophonePermissionDenied: () -> Void
    let onCameraPermissionDenied: () -> Void

    var body: some View {
        Section {
            VStack(spacing: 12) {
                VStack(spacing: 12) {
                    ProfileImageView(
                        photo: chat.chat.photo?.big,
                        minithumbnail: chat.chat.photo?.minithumbnail,
                        title: chat.displayTitle,
                        userId: chat.chat.id,
                        fontSize: 36,
                        isSavedMessages: chat.isSavedMessages,
                    )
                    .frame(width: 96, height: 96)
                    .accessibilityHidden(true)

                    Text(chat.displayTitle)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)

                    if let info {
                        badges(info)
                    }

                    Text(subtitle)
                        .font(.subheadline)
                        // Matches `telegramUserPresenceDescription`'s exact "Online" output.
                        .foregroundStyle(subtitle == "Online" ? .blue : .secondary)
                }
                .accessibilityElement(children: .combine)

                ChatInfoHeaderActionsView(
                    canStartAudioCall: info?.canStartAudioCall == true,
                    canStartVideoCall: info?.canStartVideoCall == true,
                    startAudioCall: startAudioCall,
                    startVideoCall: startVideoCall,
                    search: openConversationSearch,
                )
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    // MARK: Private

    @Environment(ChatVM.self) private var chatVM
    @Environment(\.dismiss) private var dismiss

    private var chat: CustomChat { chatVM.customChat }

    private var status: String {
        !chatVM.actionStatus.isEmpty ? chatVM.actionStatus : chatVM.conversationStatus
    }

    /// A typing/online status when there is one, otherwise a member count for groups/channels
    /// (Telegram shows "12,345 members" rather than "Group").
    private var subtitle: String {
        if !status.isEmpty { return status }
        if chat.kind == .group || chat.kind == .channel, let memberCount = info?.memberCount {
            let unit = chat.kind == .channel ? "subscriber" : "member"
            return "\(memberCount.formatted()) \(unit)\(memberCount == 1 ? "" : "s")"
        }
        return chat.kind.title
    }

    @ViewBuilder private func badges(_ info: TelegramChatInfoData) -> some View {
        if info.isScam || info.isFake || info.isVerified || info.isPremium {
            HStack(spacing: 6) {
                if info.isScam {
                    badgeCapsule("SCAM")
                }
                if info.isFake {
                    badgeCapsule("FAKE")
                }
                if info.isVerified {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.blue)
                        .accessibilityLabel("Verified")
                }
                if info.isPremium {
                    Image(systemName: "star.circle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Premium account")
                }
            }
            .font(.subheadline)
        }
    }

    private func badgeCapsule(_ text: String) -> some View {
        Text(text)
            .font(.caption2.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.red, in: Capsule())
    }

    private func startAudioCall() {
        guard let userId = info?.callUserId, info?.canStartAudioCall == true else { return }
        CallKitManager.shared.startOutgoingCall(
            userId: userId,
            displayName: chat.displayTitle,
            onMicrophonePermissionDenied: onMicrophonePermissionDenied,
        )
    }

    private func startVideoCall() {
        guard let userId = info?.callUserId, info?.canStartVideoCall == true else { return }
        CallKitManager.shared.startOutgoingCall(
            userId: userId,
            displayName: chat.displayTitle,
            isVideo: true,
            onMicrophonePermissionDenied: onMicrophonePermissionDenied,
            onCameraPermissionDenied: onCameraPermissionDenied,
        )
    }

    private func openConversationSearch() {
        dismiss()
        Task { @MainActor in
            await Task.yield()
            chatVM.beginConversationSearch()
        }
    }
}
