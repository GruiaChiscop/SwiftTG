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
    ) {
        self.id = id
        self.content = content
        self.position = position
        self.scale = scale
        self.rotationDegrees = rotationDegrees
    }

    // MARK: Internal

    let id: UUID
    var content: TelegramMediaOverlayContent
    var position: TelegramEditorPoint
    var scale: Double
    var rotationDegrees: Double
}
