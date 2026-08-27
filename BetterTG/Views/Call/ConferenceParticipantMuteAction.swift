// ConferenceParticipantMuteAction.swift

import Foundation

// MARK: - ConferenceParticipantMuteAction

enum ConferenceParticipantMuteAction: Equatable {
    case mute
    case allowToSpeak
    case muteForCurrentUser
    case unmuteForCurrentUser

    // MARK: Internal

    var title: String {
        switch self {
        case .mute:
            "Mute"
        case .allowToSpeak:
            "Allow to Speak"
        case .muteForCurrentUser:
            "Mute for Me"
        case .unmuteForCurrentUser:
            "Unmute for Me"
        }
    }

    var systemImage: String {
        switch self {
        case .mute, .muteForCurrentUser:
            "mic.slash"
        case .allowToSpeak, .unmuteForCurrentUser:
            "mic"
        }
    }

    var isMuted: Bool {
        switch self {
        case .mute, .muteForCurrentUser:
            true
        case .allowToSpeak, .unmuteForCurrentUser:
            false
        }
    }

    var isForCurrentUser: Bool {
        switch self {
        case .muteForCurrentUser, .unmuteForCurrentUser:
            true
        case .allowToSpeak, .mute:
            false
        }
    }
}
