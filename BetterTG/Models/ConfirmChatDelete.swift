// ConfirmChatDelete.swift

import TDLibKit

// MARK: - ConfirmChatDelete

struct ConfirmChatDelete {
    // MARK: Lifecycle

    init(chat: Chat?, show: Bool, deletesCommunity: Bool = false) {
        self.chat = chat
        self.show = show
        self.deletesCommunity = deletesCommunity
    }

    // MARK: Internal

    let chat: Chat?
    var show: Bool
    var deletesCommunity: Bool
}

// MARK: - ConfirmChatClearHistory

struct ConfirmChatClearHistory {
    let chat: Chat?
    var show: Bool
}

// MARK: - ConfirmChatLeave

struct ConfirmChatLeave {
    let chat: Chat?
    let isChannel: Bool
    var show: Bool
}
