// TelegramCallRatingProblem.swift

import Foundation

/// Sendable app-level representation of TDLib's generated `CallProblem`, which itself does not
/// declare concurrency conformance.
enum TelegramCallRatingProblem: String, CaseIterable, Identifiable, Sendable {
    case distortedSpeech
    case distortedVideo
    case dropped
    case echo
    case interruptions
    case noise
    case pixelatedVideo
    case silentLocal
    case silentRemote

    // MARK: Internal

    var id: String { rawValue }

    var isVideoRelated: Bool {
        switch self {
        case .distortedVideo, .pixelatedVideo:
            true
        default:
            false
        }
    }

    var title: String {
        switch self {
        case .distortedSpeech:
            "Distorted speech"
        case .distortedVideo:
            "Distorted video"
        case .dropped:
            "Call ended unexpectedly"
        case .echo:
            "I heard my own voice"
        case .interruptions:
            "Audio kept cutting out"
        case .noise:
            "Background noise"
        case .pixelatedVideo:
            "Pixelated video"
        case .silentLocal:
            "I couldn't hear the other person"
        case .silentRemote:
            "The other person couldn't hear me"
        }
    }
}
