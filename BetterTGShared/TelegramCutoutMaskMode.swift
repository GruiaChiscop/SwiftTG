// TelegramCutoutMaskMode.swift

enum TelegramCutoutMaskMode: String, CaseIterable, Identifiable, Sendable {
    case erase
    case restore

    // MARK: Internal

    var id: Self { self }

    var title: String {
        switch self {
        case .erase: "Erase"
        case .restore: "Restore"
        }
    }
}
