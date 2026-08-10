// TelegramMediaEditorSnapshot.swift

struct TelegramMediaEditorSnapshot: Equatable, Sendable {
    // MARK: Lifecycle

    init(
        strokes: [TelegramDrawingStroke],
        overlays: [TelegramMediaOverlay],
        effects: TelegramMediaEffects = .init(),
        crop: TelegramMediaCrop = .init(),
    ) {
        self.strokes = strokes
        self.overlays = overlays
        self.effects = effects
        self.crop = crop
    }

    // MARK: Internal

    var strokes: [TelegramDrawingStroke]
    var overlays: [TelegramMediaOverlay]
    var effects: TelegramMediaEffects
    var crop: TelegramMediaCrop
}
