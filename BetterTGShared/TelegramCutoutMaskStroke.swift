// TelegramCutoutMaskStroke.swift

struct TelegramCutoutMaskStroke: Equatable, Sendable {
    let points: [TelegramEditorPoint]
    let width: Double
    let mode: TelegramCutoutMaskMode
}
