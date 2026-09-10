// TelegramChatInfoCommonGroupsPage.swift

import TDLibKit

struct TelegramChatInfoCommonGroupsPage {
    let groups: [Chat]
    let hasMore: Bool
    let nextOffsetChatId: Int64
}
