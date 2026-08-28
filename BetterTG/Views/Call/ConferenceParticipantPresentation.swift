// ConferenceParticipantPresentation.swift

import Foundation

// MARK: - ConferenceParticipantPresentation

/// UI-ready participant state shared by the live conference and the local Debug laboratory.
struct ConferenceParticipantPresentation: Identifiable, Equatable {
    let id: String
    let userId: Int64?
    let chatId: Int64?
    var title: String?
    var subtitle: String
    var isSpeaking: Bool
    var isMuted: Bool
    var isHandRaised: Bool
    var isInvited: Bool
    var muteAction: ConferenceParticipantMuteAction?
    var volumeLevel = 10000
    var canAdjustVolume = false
    var canOpenConversation = false
    var canCancelSpeakRequest = false
    var canRemove = false
}
