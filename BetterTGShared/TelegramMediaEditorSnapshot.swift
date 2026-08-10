// TelegramMediaEditorSnapshot.swift

struct TelegramMediaEditorSnapshot: Equatable, Sendable {
    var strokes: [TelegramDrawingStroke]
    var overlays: [TelegramMediaOverlay]
}
