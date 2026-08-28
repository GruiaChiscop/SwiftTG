// ConferenceParticipantRow.swift

import SwiftUI
@preconcurrency import TDLibKit

// MARK: - ConferenceParticipantRow

struct ConferenceParticipantRow: View {
    // MARK: Lifecycle

    init(
        participant: ConferenceParticipantPresentation,
        isPerformingAction: Bool,
        setMuted: @escaping (ConferenceParticipantMuteAction) -> Void,
        setVolume: @escaping (Int, Bool) -> Void,
        openConversation: @escaping () -> Void,
        cancelSpeakRequest: @escaping () -> Void,
        remove: @escaping () -> Void,
    ) {
        self.participant = participant
        self.isPerformingAction = isPerformingAction
        self.setMuted = setMuted
        self.setVolume = setVolume
        self.openConversation = openConversation
        self.cancelSpeakRequest = cancelSpeakRequest
        self.remove = remove
    }

    // MARK: Internal

    var body: some View {
        if hasActions {
            Menu {
                if participant.canAdjustVolume {
                    Button("Volume", systemImage: "speaker.wave.2") {
                        showsVolumeControl = true
                    }
                }

                if let muteAction = participant.muteAction {
                    Button(muteAction.title, systemImage: muteAction.systemImage) {
                        setMuted(muteAction)
                    }
                }

                if participant.canCancelSpeakRequest {
                    Button("Cancel Request to Speak", systemImage: "hand.raised.slash") {
                        cancelSpeakRequest()
                    }
                }

                if participant.canOpenConversation {
                    Button(openConversationTitle, systemImage: openConversationSystemImage) {
                        openConversation()
                    }
                }

                if participant.canRemove {
                    Button("Remove", systemImage: "person.crop.circle.badge.xmark", role: .destructive) {
                        showsRemoveConfirmation = true
                    }
                }
            } label: {
                rowContent
            }
            .buttonStyle(.plain)
            .disabled(isPerformingAction)
            .confirmationDialog(
                "Are you sure you want to remove \(displayTitle) from this call?",
                isPresented: $showsRemoveConfirmation,
                titleVisibility: .visible,
            ) {
                Button("Remove", role: .destructive, action: remove)
                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: $showsVolumeControl) {
                ConferenceParticipantVolumeView(
                    participantName: displayTitle,
                    initialVolumeLevel: participant.volumeLevel,
                    setVolume: setVolume,
                )
            }
        } else {
            rowContent
        }
    }

    // MARK: Private

    @State private var chat: Chat?
    @State private var isChannelIdentity = false
    @State private var user: User?
    @State private var showsRemoveConfirmation = false
    @State private var showsVolumeControl = false

    private let participant: ConferenceParticipantPresentation
    private let isPerformingAction: Bool
    private let setMuted: (ConferenceParticipantMuteAction) -> Void
    private let setVolume: (Int, Bool) -> Void
    private let openConversation: () -> Void
    private let cancelSpeakRequest: () -> Void
    private let remove: () -> Void

    private var hasActions: Bool {
        participant.muteAction != nil
            || participant.canAdjustVolume
            || participant.canOpenConversation
            || participant.canCancelSpeakRequest
            || participant.canRemove
    }

    private var userId: Int64? { participant.userId }
    private var chatId: Int64? { participant.chatId }

    private var profileIdentity: String {
        participant.id
    }

    private var displayTitle: String {
        if let title = participant.title {
            return title
        } else if let user {
            return telegramUserDisplayName(user)
        }
        if let chat {
            return chat.title
        }
        return "Participant"
    }

    private var avatarId: Int64 { userId ?? chatId ?? 0 }
    private var profilePhoto: File? { user?.profilePhoto?.small ?? chat?.photo?.small }
    private var profileMinithumbnail: Minithumbnail? {
        user?.profilePhoto?.minithumbnail ?? chat?.photo?.minithumbnail
    }

    private var statusDescription: String { participant.subtitle }

    private var openConversationTitle: String {
        if participant.userId != nil {
            return "Send Message"
        }
        return isChannelIdentity ? "Open Channel" : "Open Group"
    }

    private var openConversationSystemImage: String {
        if participant.userId != nil {
            return "message"
        }
        return isChannelIdentity ? "megaphone" : "person.2"
    }

    private var statusSystemImage: String {
        if participant.isInvited {
            return "person.crop.circle.badge.clock"
        }
        if participant.isSpeaking {
            return "mic.fill"
        }
        if participant.isHandRaised {
            return "hand.raised.fill"
        }
        if participant.isMuted {
            return "mic.slash.fill"
        }
        return "mic.fill"
    }

    private var statusColor: Color {
        if participant.isSpeaking {
            return .green
        }
        if participant.isHandRaised {
            return .orange
        }
        if participant.isMuted {
            return .red
        }
        return .secondary
    }

    private var rowContent: some View {
        HStack(spacing: 12) {
            ProfileImageView(
                photo: profilePhoto,
                minithumbnail: profileMinithumbnail,
                title: displayTitle,
                userId: avatarId,
            )
            .frame(width: 44, height: 44)
            .overlay {
                if participant.isSpeaking {
                    Circle()
                        .stroke(.green, lineWidth: 2)
                }
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(displayTitle)
                    .font(.body.bold())
                    .lineLimit(1)
                Text(statusDescription)
                    .font(.subheadline)
                    .foregroundStyle(statusColor)
            }

            Spacer()

            if isPerformingAction {
                ProgressView()
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: statusSystemImage)
                    .foregroundStyle(statusColor)
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .task(id: profileIdentity) {
            await loadProfile()
        }
    }

    @MainActor private func loadProfile() async {
        user = nil
        chat = nil
        isChannelIdentity = false
        guard participant.title == nil else { return }
        let service = TDLib.shared.service
        do {
            if let userId {
                let loadedUser = try await service.getUser(userId: userId)
                try Task.checkCancellation()
                user = loadedUser
            } else if let chatId {
                let loadedChat = try await service.getChat(chatId: chatId)
                try Task.checkCancellation()
                chat = loadedChat
                if case .chatTypeSupergroup(let supergroupType) = loadedChat.type,
                   let supergroup = try? await service.getSupergroup(supergroupId: supergroupType.supergroupId)
                {
                    guard !Task.isCancelled else { return }
                    isChannelIdentity = supergroup.isChannel
                }
            }
        } catch is CancellationError {
            return
        } catch {
            log("[GroupCall] couldn't load participant profile \(profileIdentity): \(error)")
        }
    }
}
