// TelegramBrushStyle.swift

enum TelegramBrushStyle: String, CaseIterable, Identifiable, Sendable {
    case pen
    case marker
    case highlighter
    case neon

    // MARK: Internal

    var id: Self { self }

    var title: String {
        switch self {
        case .pen: "Pen"
        case .marker: "Marker"
        case .highlighter: "Highlighter"
        case .neon: "Neon"
        }
    }

    var widthMultiplier: Double {
        switch self {
        case .neon, .pen: 1
        case .marker: 1.5
        case .highlighter: 2
        }
    }

    var opacity: Double {
        switch self {
        case .neon, .pen: 1
        case .marker: 0.85
        case .highlighter: 0.35
        }
    }
}
