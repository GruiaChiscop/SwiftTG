// TelegramDrawingStroke.swift

import Foundation

struct TelegramDrawingStroke: Identifiable, Equatable, Sendable {
    // MARK: Lifecycle

    init(
        id: UUID = UUID(),
        points: [TelegramEditorPoint],
        color: TelegramEditorColor,
        width: Double,
    ) {
        self.id = id
        self.points = points
        self.color = color
        self.width = width
    }

    // MARK: Internal

    let id: UUID
    var points: [TelegramEditorPoint]
    var color: TelegramEditorColor
    var width: Double
}
