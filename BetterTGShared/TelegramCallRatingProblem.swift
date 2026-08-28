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
            "Speech was distorted"
        case .distortedVideo:
            "Video was distorted"
        case .dropped:
            "Call ended unexpectedly"
        case .echo:
            "I heard my own voice"
        case .interruptions:
            "The other side kept disappearing"
        case .noise:
            "I heard background noise"
        case .pixelatedVideo:
            "Pixelated video"
        case .silentLocal:
            "I couldn't hear the other side"
        case .silentRemote:
            "The other side couldn't hear me"
        }
    }

    var hashtag: String {
        switch self {
        case .distortedSpeech: "distorted_speech"
        case .distortedVideo: "distorted_video"
        case .dropped: "dropped"
        case .echo: "echo"
        case .interruptions: "interruptions"
        case .noise: "noise"
        case .pixelatedVideo: "pixelated_video"
        case .silentLocal: "silent_local"
        case .silentRemote: "silent_remote"
        }
    }
}
