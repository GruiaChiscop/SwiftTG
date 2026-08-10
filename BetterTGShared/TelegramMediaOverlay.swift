// TelegramMediaOverlay.swift

import Foundation

struct TelegramMediaOverlay: Identifiable, Equatable, Sendable {
    // MARK: Lifecycle

    init(
        id: UUID = UUID(),
        content: TelegramMediaOverlayContent,
        position: TelegramEditorPoint = .init(x: 0.5, y: 0.5),
        scale: Double = 1,
        rotationDegrees: Double = 0,
        startTime: Double = 0,
        endTime: Double = .greatestFiniteMagnitude,
    ) {
        self.id = id
        self.content = content
        self.position = position
        self.scale = scale
        self.rotationDegrees = rotationDegrees
        self.startTime = startTime
        self.endTime = endTime
    }

    // MARK: Internal

    let id: UUID
    var content: TelegramMediaOverlayContent
    var position: TelegramEditorPoint
    var scale: Double
    var rotationDegrees: Double
    var startTime: Double
    var endTime: Double

    func isVisible(at time: Double) -> Bool {
        time >= startTime && time <= endTime
    }
}
