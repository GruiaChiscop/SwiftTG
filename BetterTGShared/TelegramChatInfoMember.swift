// TelegramChatInfoMember.swift

import Foundation
import TDLibKit

struct TelegramChatInfoMember: Identifiable, Equatable, Sendable {
    // MARK: Lifecycle

    init(
        id: MessageSender,
        name: String,
        role: String?,
        presence: String?,
        photo: File?,
        minithumbnail: Minithumbnail?,
        placeholderId: Int64,
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.presence = presence
        self.photo = photo
        self.minithumbnailStorage = minithumbnail.map(MinithumbnailStorage.init)
        self.placeholderId = placeholderId
    }

    // MARK: Internal

    let id: MessageSender
    let name: String
    let role: String?
    let presence: String?
    let photo: File?
    let placeholderId: Int64

    var minithumbnail: Minithumbnail? {
        minithumbnailStorage.map {
            Minithumbnail(data: $0.data, height: $0.height, width: $0.width)
        }
    }

    // MARK: Private

    private struct MinithumbnailStorage: Equatable, Sendable {
        // MARK: Lifecycle

        init(_ minithumbnail: Minithumbnail) {
            self.data = minithumbnail.data
            self.height = minithumbnail.height
            self.width = minithumbnail.width
        }

        // MARK: Internal

        let data: Data
        let height: Int
        let width: Int
    }

    private let minithumbnailStorage: MinithumbnailStorage?
}
