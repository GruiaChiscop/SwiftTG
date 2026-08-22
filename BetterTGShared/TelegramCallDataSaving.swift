// TelegramCallDataSaving.swift

enum TelegramCallDataSaving: String, CaseIterable, Hashable, Identifiable {
    case never
    case cellular
    case always

    // MARK: Internal

    var id: Self { self }

    var title: String {
        switch self {
        case .never: "Never"
        case .cellular: "On Mobile Network"
        case .always: "Always"
        }
    }
}
