// TelegramShareExtension.swift

import Foundation

// MARK: - TelegramShareExtension

/// Shared App Group plumbing between the main app and the Share Extension - the extension has no
/// TDLib access of its own (a second process can't open the same TDLib database directory the
/// main app already has locked), so everything here is plain file/UserDefaults I/O, not TDLib.
enum TelegramShareExtension {
    static let appGroupId = "group.com.gruiachiscop.BetterTG"

    static var appGroupContainerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId)
    }
}

// MARK: - ShareTargetChat

/// A lightweight, cached stand-in for a chat - no photo, since the extension can't download TDLib
/// files either (same reasoning as the initials-only avatar rows already used on macOS).
struct ShareTargetChat: Codable, Identifiable, Equatable {
    let id: Int64
    let title: String
    let isSavedMessages: Bool
    let kind: ShareChatKind
}

// MARK: - ShareChatKind

/// Deliberately its own type rather than reusing `ChatListItemKind` - that one lives in
/// `TelegramChatListStore.swift` and imports TDLibKit, which the Share Extension target must never
/// link (it never touches TDLib - see `TelegramShareExtension` above).
enum ShareChatKind: String, Sendable, Equatable, Codable {
    case privateChat
    case group
    case channel
    case secretChat
}

// MARK: - ShareChatCache

enum ShareChatCache {
    // MARK: Internal

    static func save(_ chats: [ShareTargetChat]) {
        guard let defaults, let data = try? JSONEncoder().encode(chats) else { return }
        defaults.set(data, forKey: key)
    }

    static func load() -> [ShareTargetChat] {
        guard let defaults,
              let data = defaults.data(forKey: key),
              let chats = try? JSONDecoder().decode([ShareTargetChat].self, from: data)
        else { return [] }
        return chats
    }

    // MARK: Private

    private static let key = "TelegramShareExtension.chats.v1"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: TelegramShareExtension.appGroupId)
    }
}

// MARK: - ShareRequest

struct ShareRequest: Codable {
    let id: String
    let createdAt: TimeInterval
    let chatIds: [Int64]
    let comment: String?
    /// File names relative to this request's own `filesDirectory`.
    let files: [String]
}

// MARK: - ShareRequestStore

enum ShareRequestStore {
    // MARK: Internal

    static func requestDirectory(id: String) -> URL? {
        TelegramShareExtension.appGroupContainerURL?
            .appending(path: requestsDirectoryName, directoryHint: .isDirectory)
            .appending(path: id, directoryHint: .isDirectory)
    }

    static func filesDirectory(id: String) -> URL? {
        requestDirectory(id: id)?.appending(path: filesDirectoryName, directoryHint: .isDirectory)
    }

    static func write(_ request: ShareRequest) throws {
        guard let dir = requestDirectory(id: request.id), let manifestURL = manifestURL(id: request.id) else {
            throw CocoaError(.fileNoSuchFile)
        }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(request)
        try data.write(to: manifestURL, options: .atomic)
    }

    static func load(id: String) -> ShareRequest? {
        guard let manifestURL = manifestURL(id: id), let data = try? Data(contentsOf: manifestURL) else { return nil }
        return try? JSONDecoder().decode(ShareRequest.self, from: data)
    }

    static func delete(id: String) {
        guard let dir = requestDirectory(id: id) else { return }
        try? FileManager.default.removeItem(at: dir)
    }

    static func pendingRequestIds() -> [String] {
        guard let base = TelegramShareExtension.appGroupContainerURL else { return [] }
        let queueDir = base.appending(path: requestsDirectoryName, directoryHint: .isDirectory)
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: queueDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles],
        ) else { return [] }
        return urls
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map(\.lastPathComponent)
    }

    // MARK: Private

    private static let requestsDirectoryName = "ShareRequests"
    private static let manifestName = "request.json"
    private static let filesDirectoryName = "files"

    private static func manifestURL(id: String) -> URL? {
        requestDirectory(id: id)?.appending(path: manifestName, directoryHint: .notDirectory)
    }
}
