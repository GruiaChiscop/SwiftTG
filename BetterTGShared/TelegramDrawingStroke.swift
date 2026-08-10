// TelegramDrawingStroke.swift

import Foundation

struct TelegramDrawingStroke: Identifiable, Equatable, Sendable {
    // MARK: Lifecycle

    init(
        id: UUID = UUID(),
        points: [TelegramEditorPoint],
        color: TelegramEditorColor,
        width: Double,
        style: TelegramBrushStyle = .pen,
    ) {
        self.id = id
        self.points = points
        self.color = color
        self.width = width
        self.style = style
    }

    // MARK: Internal

    let id: UUID
    var points: [TelegramEditorPoint]
    var color: TelegramEditorColor
    var width: Double
    var style: TelegramBrushStyle
}
