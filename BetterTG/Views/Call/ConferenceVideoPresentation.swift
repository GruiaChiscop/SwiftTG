// ConferenceVideoPresentation.swift

import Foundation

// MARK: - ConferenceVideoPresentation

struct ConferenceVideoPresentation: Identifiable, Equatable {
    let id: String
    let participantId: String
    let endpointId: String
    let userId: Int64?
    let chatId: Int64?
    let title: String?
    let isScreenSharing: Bool
    let isPaused: Bool
}
