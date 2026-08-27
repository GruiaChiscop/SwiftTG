// ConferenceIncomingVideoQuality.swift

import Foundation

// MARK: - ConferenceIncomingVideoQuality

/// Telegram-iOS's four global limits for received conference video.
enum ConferenceIncomingVideoQuality: Int, CaseIterable, Identifiable, Sendable {
    case audioOnly
    case p180
    case p360
    case p720

    // MARK: Internal

    var id: Self { self }

    var title: String {
        switch self {
        case .audioOnly: "Audio Only"
        case .p180: "180p"
        case .p360: "360p"
        case .p720: "720p"
        }
    }
}
