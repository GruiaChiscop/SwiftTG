// TelegramMediaPickerTab.swift

enum TelegramMediaPickerTab: String, CaseIterable, Identifiable {
    case stickers
    case gifs

    // MARK: Internal

    static let defaultsKey = "telegram.mediaPicker.selectedTab"

    var id: Self { self }

    var title: String {
        switch self {
        case .stickers: "Stickers"
        case .gifs: "GIFs"
        }
    }

    static func selection(storedValue: String) -> Self {
        Self(rawValue: storedValue) ?? .stickers
    }
}
