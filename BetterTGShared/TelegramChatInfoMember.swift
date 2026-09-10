// TelegramChatInfoMember.swift

import TDLibKit

struct TelegramChatInfoMember: Identifiable, Equatable {
    let id: MessageSender
    let name: String
    let role: String?
    let presence: String?
    let photo: File?
    let minithumbnail: Minithumbnail?
    let placeholderId: Int64
}
