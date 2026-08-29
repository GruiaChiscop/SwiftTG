// ConferenceVideoParticipantTile.swift

import SwiftUI
@preconcurrency import TDLibKit

// MARK: - ConferenceVideoParticipantTile

struct ConferenceVideoParticipantTile: View {
    // MARK: Internal

    let video: ConferenceVideoPresentation
    let participant: ConferenceParticipantPresentation
    let isPerformingAction: Bool
    let select: (ConferenceVideoPresentation) -> Void
    let setMuted: (ConferenceParticipantMuteAction) -> Void
    let setVolume: (Int, Bool) -> Void
    let openConversation: () -> Void
    let remove: () -> Void
    let requestVideoView: (String, @escaping @MainActor (UIView?) -> Void) -> Void

    var body: some View {
        Button {
            select(video)
        } label: {
            ConferenceVideoTileView(
                video: video,
                requestVideoView: requestVideoView,
            )
        }
        .buttonStyle(.plain)
        .disabled(isPerformingAction)
        .contextMenu {
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
        }
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
        .task(id: participant.id) {
            await loadProfile()
        }
    }

    // MARK: Private

    @State private var chat: Chat?
    @State private var isChannelIdentity = false
    @State private var showsRemoveConfirmation = false
    @State private var showsVolumeControl = false
    @State private var user: User?

    private var displayTitle: String {
        if let title = participant.title ?? video.title {
            return title
        } else if let user {
            return telegramUserDisplayName(user)
        } else if let chat {
            return chat.title
        }
        return "Participant"
    }

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

    @MainActor private func loadProfile() async {
        user = nil
        chat = nil
        isChannelIdentity = false
        guard participant.title == nil, video.title == nil else { return }

        let service = TDLib.shared.service
        do {
            if let userId = participant.userId {
                let loadedUser = try await service.getUser(userId: userId)
                try Task.checkCancellation()
                user = loadedUser
            } else if let chatId = participant.chatId {
                let loadedChat = try await service.getChat(chatId: chatId)
                try Task.checkCancellation()
                chat = loadedChat
                if case .chatTypeSupergroup(let supergroupType) = loadedChat.type,
                   let supergroup = try? await service.getSupergroup(supergroupId: supergroupType.supergroupId)
                {
                    try Task.checkCancellation()
                    isChannelIdentity = supergroup.isChannel
                }
            }
        } catch is CancellationError {
            return
        } catch {
            log("[GroupCall] couldn't load video participant profile \(participant.id): \(error)")
        }
    }
}
