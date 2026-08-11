// TelegramComposerInputMode.swift

enum TelegramComposerInputMode: Equatable, Sendable {
    case media
    case text

    // MARK: Internal

    var allowsTextControls: Bool {
        self == .text
    }

    var mediaButtonSystemImage: String {
        switch self {
        case .media: "keyboard"
        case .text: "face.smiling"
        }
    }

    var mediaButtonTitle: String {
        switch self {
        case .media: "Return to Keyboard"
        case .text: "Stickers and GIFs"
        }
    }
}
