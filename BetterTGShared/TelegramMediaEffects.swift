// TelegramMediaEffects.swift

struct TelegramMediaEffects: Equatable, Sendable {
    var brightness = 0.0
    var contrast = 1.0
    var saturation = 1.0
    var blurRadius = 0.0

    var isIdentity: Bool {
        self == TelegramMediaEffects()
    }
}
