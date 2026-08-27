// ConferenceLabModel.swift

#if DEBUG
import Foundation
import Observation

// MARK: - ConferenceLabModel

@MainActor
@Observable final class ConferenceLabModel {
    // MARK: Internal

    private(set) var participants = initialParticipants()
    private(set) var videos = initialVideos()
    private(set) var connectionStatus: String?
    private(set) var verificationEmojis = initialVerificationEmojis
    private(set) var isEnded = false
    private(set) var announcementSequence = 0
    private(set) var lastAnnouncement = ""

    var participantCount: Int { participants.count(where: { !$0.isInvited }) }
    var hasInvitedParticipant: Bool { participants.contains(where: \.isInvited) }
    var hasAlex: Bool { participant(named: "Alex") != nil }
    var hasRemovableParticipant: Bool { participants.contains(where: { $0.id != "lab-you" }) }
    var canAddDana: Bool { participant(id: "lab-dana") == nil }
    var canInviteSorin: Bool { participant(id: "lab-sorin") == nil }
    var isAlexSpeaking: Bool { participant(named: "Alex")?.isSpeaking == true }
    var isAlexMuted: Bool { participant(named: "Alex")?.isMuted == true }
    var isAlexHandRaised: Bool { participant(named: "Alex")?.isHandRaised == true }
    var isCurrentUserMuted: Bool { participant(id: "lab-you")?.isMuted == true }
    var isReconnecting: Bool { connectionStatus != nil }
    var isMaraCameraEnabled: Bool { videos.contains(where: { $0.id == "lab-mara-camera" }) }
    var isAlexScreenSharing: Bool { videos.contains(where: { $0.id == "lab-alex-screen" }) }
    var isAlexConnected: Bool { participant(named: "Alex")?.isInvited == false }

    func connectInvitedParticipant() {
        guard let index = participants.firstIndex(where: \.isInvited) else { return }
        participants[index].isInvited = false
        participants[index].subtitle = "Listening"
        participants[index].muteAction = .mute
        advanceVerificationEmojis()
        announce("\(participants[index].title ?? "Participant") joined the group call")
    }

    func toggleAlexSpeaking() {
        updateParticipant(named: "Alex") { participant in
            participant.isSpeaking.toggle()
            if participant.isSpeaking {
                participant.isInvited = false
                participant.isMuted = false
                participant.isHandRaised = false
                participant.subtitle = "Speaking"
                participant.muteAction = .mute
            } else {
                participant.subtitle = participant.isMuted ? "Muted" : "Listening"
            }
        }
        announce(isAlexSpeaking ? "Alex is speaking" : "Alex stopped speaking")
    }

    func toggleAlexMuted() {
        updateParticipant(named: "Alex") { participant in
            participant.isInvited = false
            participant.isMuted.toggle()
            participant.isSpeaking = false
            participant.isHandRaised = false
            participant.subtitle = participant.isMuted ? "Muted" : "Listening"
            participant.muteAction = participant.isMuted ? .allowToSpeak : .mute
        }
        announce(isAlexMuted ? "Alex's microphone is off" : "Alex's microphone is on")
    }

    func toggleAlexHandRaised() {
        updateParticipant(named: "Alex") { participant in
            participant.isInvited = false
            participant.isHandRaised.toggle()
            participant.isSpeaking = false
            participant.isMuted = participant.isHandRaised
            participant.subtitle = participant.isHandRaised ? "Hand raised" : "Listening"
            participant.muteAction = participant.isHandRaised ? .allowToSpeak : .mute
        }
        announce(isAlexHandRaised ? "Alex raised a hand" : "Alex lowered a hand")
    }

    func toggleCurrentUserMuted() {
        updateParticipant(id: "lab-you") { participant in
            participant.isMuted.toggle()
        }
    }

    func toggleReconnecting() {
        connectionStatus = connectionStatus == nil ? "Connecting" : nil
        announce(connectionStatus == nil ? "Group call connected" : "Group call reconnecting")
    }

    func addParticipant() {
        guard participant(id: "lab-dana") == nil else { return }
        participants.append(ConferenceParticipantPresentation(
            id: "lab-dana",
            userId: nil,
            chatId: nil,
            title: "Dana",
            subtitle: "Listening",
            isSpeaking: false,
            isMuted: false,
            isHandRaised: false,
            isInvited: false,
            muteAction: .mute,
            canRemove: true,
        ))
        advanceVerificationEmojis()
        announce("Dana joined the group call")
    }

    func inviteParticipant() {
        guard canInviteSorin else { return }
        participants.append(ConferenceParticipantPresentation(
            id: "lab-sorin",
            userId: nil,
            chatId: nil,
            title: "Sorin",
            subtitle: "Invited",
            isSpeaking: false,
            isMuted: false,
            isHandRaised: false,
            isInvited: true,
            canRemove: true,
        ))
        announce("Sorin was invited")
    }

    func removeParticipant() {
        guard let index = participants.lastIndex(where: { $0.id != "lab-you" }) else { return }
        let name = participants[index].title ?? "Participant"
        let participantId = participants[index].id
        let wasInvited = participants[index].isInvited
        participants.remove(at: index)
        videos.removeAll(where: { $0.participantId == participantId })
        if !wasInvited {
            advanceVerificationEmojis()
        }
        announce("\(name) left the group call")
    }

    func setParticipantMuted(
        _ participant: ConferenceParticipantPresentation,
        action: ConferenceParticipantMuteAction,
    ) {
        updateParticipant(id: participant.id) { participant in
            participant.isMuted = action.isMuted
            participant.isSpeaking = false
            participant.subtitle = action.isMuted ? "Muted" : "Listening"
            participant.muteAction =
 switch action {
            case .mute:
                .allowToSpeak
            case .allowToSpeak:
                .mute
            case .muteForCurrentUser:
                .unmuteForCurrentUser
            case .unmuteForCurrentUser:
                .muteForCurrentUser
            }
        }
    }

    func removeParticipant(_ participant: ConferenceParticipantPresentation) {
        guard let index = participants.firstIndex(where: { $0.id == participant.id }) else { return }
        let name = participants[index].title ?? "Participant"
        let wasInvited = participants[index].isInvited
        participants.remove(at: index)
        videos.removeAll(where: { $0.participantId == participant.id })
        if !wasInvited {
            advanceVerificationEmojis()
        }
        announce("\(name) left the group call")
    }

    func endConference() {
        guard !isEnded else { return }
        isEnded = true
        announce("Group call ended")
    }

    func toggleMaraCamera() {
        if isMaraCameraEnabled {
            videos.removeAll(where: { $0.id == "lab-mara-camera" })
        } else {
            videos.append(Self.maraCamera)
        }
    }

    func toggleAlexScreenSharing() {
        guard isAlexConnected else { return }
        if isAlexScreenSharing {
            videos.removeAll(where: { $0.id == "lab-alex-screen" })
        } else {
            videos.append(Self.alexScreen)
        }
    }

    func reset() {
        participants = Self.initialParticipants()
        videos = Self.initialVideos()
        connectionStatus = nil
        verificationEmojis = Self.initialVerificationEmojis
        isEnded = false
        announce("Conference laboratory reset")
    }

    // MARK: Private

    private static let initialVerificationEmojis = ["🦋", "🌵", "🚀", "🍀"]
    private static let alternateVerificationEmojis = ["🐳", "🍓", "🎸", "🌙"]

    private static let maraCamera = ConferenceVideoPresentation(
        id: "lab-mara-camera",
        participantId: "lab-mara",
        endpointId: "lab-mara-camera-endpoint",
        userId: nil,
        chatId: nil,
        title: "Mara",
        isScreenSharing: false,
        isPaused: false,
    )
    private static let alexScreen = ConferenceVideoPresentation(
        id: "lab-alex-screen",
        participantId: "lab-alex",
        endpointId: "lab-alex-screen-endpoint",
        userId: nil,
        chatId: nil,
        title: "Alex",
        isScreenSharing: true,
        isPaused: false,
    )

    private static func initialVideos() -> [ConferenceVideoPresentation] {
        [maraCamera]
    }

    private static func initialParticipants() -> [ConferenceParticipantPresentation] {
        [
            ConferenceParticipantPresentation(
                id: "lab-you",
                userId: nil,
                chatId: nil,
                title: "Gruia",
                subtitle: "You",
                isSpeaking: false,
                isMuted: false,
                isHandRaised: false,
                isInvited: false,
            ),
            ConferenceParticipantPresentation(
                id: "lab-alex",
                userId: nil,
                chatId: nil,
                title: "Alex",
                subtitle: "Invited",
                isSpeaking: false,
                isMuted: false,
                isHandRaised: false,
                isInvited: true,
                canRemove: true,
            ),
            ConferenceParticipantPresentation(
                id: "lab-mara",
                userId: nil,
                chatId: nil,
                title: "Mara",
                subtitle: "Listening",
                isSpeaking: false,
                isMuted: false,
                isHandRaised: false,
                isInvited: false,
                muteAction: .mute,
                canRemove: true,
            ),
        ]
    }

    private func advanceVerificationEmojis() {
        verificationEmojis = verificationEmojis == Self.initialVerificationEmojis
            ? Self.alternateVerificationEmojis
            : Self.initialVerificationEmojis
    }

    private func participant(id: String) -> ConferenceParticipantPresentation? {
        participants.first(where: { $0.id == id })
    }

    private func participant(named name: String) -> ConferenceParticipantPresentation? {
        participants.first(where: { $0.title == name })
    }

    private func updateParticipant(
        id: String,
        mutation: (inout ConferenceParticipantPresentation) -> Void,
    ) {
        guard let index = participants.firstIndex(where: { $0.id == id }) else { return }
        mutation(&participants[index])
    }

    private func updateParticipant(
        named name: String,
        mutation: (inout ConferenceParticipantPresentation) -> Void,
    ) {
        guard let index = participants.firstIndex(where: { $0.title == name }) else { return }
        mutation(&participants[index])
    }

    private func announce(_ message: String) {
        lastAnnouncement = message
        announcementSequence += 1
    }
}
#endif
