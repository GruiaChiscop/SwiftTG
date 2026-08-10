// TelegramEditorOverlayPickerSection.swift

enum TelegramEditorOverlayPickerSection: String, CaseIterable, Identifiable, Sendable {
    case stickers
    case gifs

    // MARK: Internal

    var id: Self { self }

    var title: String {
        switch self {
        case .stickers: "Stickers"
        case .gifs: "GIFs"
        }
    }

    var systemImage: String {
        switch self {
        case .stickers: "face.smiling"
        case .gifs: "photo.on.rectangle"
        }
    }

    var searchPrompt: String {
        switch self {
        case .stickers: "Search stickers"
        case .gifs: "Search GIFs"
        }
    }
}
