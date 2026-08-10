// TelegramStickerPackInstallationAction.swift

enum TelegramStickerPackInstallationAction: Equatable, Sendable {
    case install(stickerCount: Int)
    case remove(stickerCount: Int)

    // MARK: Lifecycle

    init?(isInstalled: Bool, isOwned: Bool, stickerCount: Int) {
        guard !isOwned else { return nil }
        self = isInstalled ? .remove(stickerCount: stickerCount) : .install(stickerCount: stickerCount)
    }

    // MARK: Internal

    var installs: Bool {
        if case .install = self {
            true
        } else {
            false
        }
    }

    var title: String {
        let count =
            switch self {
            case .install(let stickerCount), .remove(let stickerCount): stickerCount
            }
        let noun = count == 1 ? "Sticker" : "Stickers"
        return "\(installs ? "Add" : "Remove") \(count) \(noun)"
    }
}
