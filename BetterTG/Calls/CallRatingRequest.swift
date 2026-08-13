// CallRatingRequest.swift

import Foundation

struct CallRatingRequest: Equatable, Identifiable, Sendable {
    let callId: Int
    let isVideo: Bool

    var id: Int { callId }
}
