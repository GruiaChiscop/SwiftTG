// ConferenceLabView.swift

#if DEBUG
import SwiftUI

// MARK: - ConferenceLabView

struct ConferenceLabView: View {
    // MARK: Internal

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            if model.isEnded {
                ContentUnavailableView(
                    "Conference Ended",
                    systemImage: "phone.down.fill",
                    description: Text("Use Reset in the Simulate menu to begin again."),
                )
            } else {
                VStack(spacing: 12) {
                    Text("Local simulation. No Telegram call is made.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    ConferenceParticipantsView(
                        participants: model.participants,
                        localVideoView: nil,
                        isLocalScreenSharing: false,
                        videos: model.videos,
                        participantCount: model.participantCount,
                        connectionStatus: model.connectionStatus,
                        verificationEmojis: model.verificationEmojis,
                        inviteLink: URL(string: "https://t.me/call/conference-lab"),
                        isInvitingParticipant: false,
                        performingParticipantActionId: nil,
                        inviteParticipant: model.inviteParticipant,
                        setParticipantMuted: model.setParticipantMuted,
                        removeParticipant: model.removeParticipant,
                        loadMoreParticipants: {},
                        requestVideoView: { _, completion in completion(nil) },
                    )
                }
                .safeAreaPadding()
                .padding(.horizontal)
            }
        }
        .navigationTitle("Conference Lab")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu("Simulate", systemImage: "slider.horizontal.3") {
                    Section("Participants") {
                        Button("Connect Invited Participant", systemImage: "person.crop.circle.badge.checkmark") {
                            model.connectInvitedParticipant()
                        }
                        .disabled(!model.hasInvitedParticipant || model.isEnded)

                        Button(
                            model.isAlexSpeaking ? "Stop Alex Speaking" : "Start Alex Speaking",
                            systemImage: model.isAlexSpeaking ? "waveform.slash" : "waveform",
                            action: model.toggleAlexSpeaking,
                        )
                        .disabled(!model.hasAlex || model.isEnded)

                        Button(
                            model.isAlexMuted ? "Unmute Alex" : "Mute Alex",
                            systemImage: model.isAlexMuted ? "mic.fill" : "mic.slash.fill",
                            action: model.toggleAlexMuted,
                        )
                        .disabled(!model.hasAlex || model.isEnded)

                        Button(
                            model.isAlexHandRaised ? "Lower Alex's Hand" : "Raise Alex's Hand",
                            systemImage: "hand.raised.fill",
                            action: model.toggleAlexHandRaised,
                        )
                        .disabled(!model.hasAlex || model.isEnded)

                        Button(
                            model.isCurrentUserMuted ? "Unmute Yourself" : "Mute Yourself",
                            systemImage: model.isCurrentUserMuted ? "mic.fill" : "mic.slash.fill",
                            action: model.toggleCurrentUserMuted,
                        )
                        .disabled(model.isEnded)
                    }

                    Section("Lifecycle") {
                        Button(
                            model.isReconnecting ? "Restore Connection" : "Simulate Reconnecting",
                            systemImage: model.isReconnecting ? "wifi" : "wifi.exclamationmark",
                            action: model.toggleReconnecting,
                        )
                        .disabled(model.isEnded)

                        Button("Add Dana", systemImage: "person.badge.plus", action: model.addParticipant)
                            .disabled(!model.canAddDana || model.isEnded)
                        Button(
                            "Remove Last Participant",
                            systemImage: "person.badge.minus",
                            action: model.removeParticipant,
                        )
                            .disabled(!model.hasRemovableParticipant || model.isEnded)
                        Button(
                            "End Conference",
                            systemImage: "phone.down.fill",
                            role: .destructive,
                            action: model.endConference,
                        )
                            .disabled(model.isEnded)
                    }

                    Section("Video") {
                        Button(
                            model.isMaraCameraEnabled ? "Stop Mara's Camera" : "Start Mara's Camera",
                            systemImage: model.isMaraCameraEnabled ? "video.slash.fill" : "video.fill",
                            action: model.toggleMaraCamera,
                        )
                        .disabled(model.isEnded)

                        Button(
                            model.isAlexScreenSharing ? "Stop Alex's Screen" : "Share Alex's Screen",
                            systemImage: model.isAlexScreenSharing
                                ? "rectangle.on.rectangle.slash"
                                : "rectangle.on.rectangle",
                            action: model.toggleAlexScreenSharing,
                        )
                        .disabled(!model.isAlexConnected || model.isEnded)
                    }

                    Button("Reset", systemImage: "arrow.counterclockwise", action: model.reset)
                }
            }
        }
        .task(id: model.announcementSequence) {
            guard !model.lastAnnouncement.isEmpty else { return }
            do {
                try await Task.sleep(for: .milliseconds(300))
            } catch {
                return
            }
            AccessibilityNotification.Announcement(model.lastAnnouncement).post()
        }
    }

    // MARK: Private

    @State private var model = ConferenceLabModel()
}
#endif
