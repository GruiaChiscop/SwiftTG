// ConferenceLabModel.swift

#if DEBUG
import Foundation
import Observation

// MARK: - ConferenceLabModel

@MainActor
@Observable final class ConferenceLabModel {
    // MARK: Internal

    private(set) var participants = initialParticipants()
    private(set) var connectionStatus: String?
    private(set) var isEnded = false
    private(set) var announcementSequence = 0
    private(set) var lastAnnouncement = ""

    var participantCount: Int { participants.count(where: { !$0.isInvited }) }
    var hasInvitedParticipant: Bool { participants.contains(where: \.isInvited) }
    var hasAlex: Bool { participant(named: "Alex") != nil }
    var hasRemovableParticipant: Bool { participants.contains(where: { $0.id != "lab-you" }) }
    var canAddDana: Bool { participant(id: "lab-dana") == nil }
    var isAlexSpeaking: Bool { participant(named: "Alex")?.isSpeaking == true }
    var isAlexMuted: Bool { participant(named: "Alex")?.isMuted == true }
    var isAlexHandRaised: Bool { participant(named: "Alex")?.isHandRaised == true }
    var isCurrentUserMuted: Bool { participant(id: "lab-you")?.isMuted == true }
    var isReconnecting: Bool { connectionStatus != nil }

    func connectInvitedParticipant() {
        guard let index = participants.firstIndex(where: \.isInvited) else { return }
        participants[index].isInvited = false
        participants[index].subtitle = "Listening"
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
        ))
        announce("Dana joined the group call")
    }

    func removeParticipant() {
        guard let index = participants.lastIndex(where: { $0.id != "lab-you" }) else { return }
        let name = participants[index].title ?? "Participant"
        participants.remove(at: index)
        announce("\(name) left the group call")
    }

    func endConference() {
        guard !isEnded else { return }
        isEnded = true
        announce("Group call ended")
    }

    func reset() {
        participants = Self.initialParticipants()
        connectionStatus = nil
        isEnded = false
        announce("Conference laboratory reset")
    }

    // MARK: Private

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
            ),
        ]
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
