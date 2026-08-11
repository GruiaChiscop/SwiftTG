// TelegramMediaSendPermissionTests.swift

@testable import BetterTG
import TDLibKit
import Testing

struct TelegramMediaSendPermissionTests {
    @Test func `ordinary members follow the chat media permission`() {
        let member = ChatMemberStatus.chatMemberStatusMember(.init(memberUntilDate: 0))

        #expect(TelegramMediaSendPermission.allowsSending(
            defaultPermissions: TDLibFixtures.permissions(canSendOtherMessages: true),
            status: member,
            isChannel: false,
        ))
        #expect(!TelegramMediaSendPermission.allowsSending(
            defaultPermissions: TDLibFixtures.permissions(canSendOtherMessages: false),
            status: member,
            isChannel: false,
        ))
        #expect(!TelegramMediaSendPermission.allowsSending(
            defaultPermissions: TDLibFixtures.permissions(canSendOtherMessages: true),
            status: member,
            isChannel: true,
        ))
    }

    @Test func `creator and restricted member states override default permissions correctly`() {
        let denied = TDLibFixtures.permissions(canSendOtherMessages: false)
        let allowed = TDLibFixtures.permissions(canSendOtherMessages: true)
        let creator = ChatMemberStatus.chatMemberStatusCreator(.init(isAnonymous: false, isMember: true))
        let restricted = ChatMemberStatus.chatMemberStatusRestricted(.init(
            isMember: true,
            permissions: allowed,
            restrictedUntilDate: 0,
        ))
        let removed = ChatMemberStatus.chatMemberStatusRestricted(.init(
            isMember: false,
            permissions: allowed,
            restrictedUntilDate: 0,
        ))

        #expect(TelegramMediaSendPermission.allowsSending(
            defaultPermissions: denied,
            status: creator,
            isChannel: false,
        ))
        #expect(TelegramMediaSendPermission.allowsSending(
            defaultPermissions: denied,
            status: restricted,
            isChannel: false,
        ))
        #expect(!TelegramMediaSendPermission.allowsSending(
            defaultPermissions: allowed,
            status: removed,
            isChannel: false,
        ))
    }

    @Test func `restriction descriptions match the active media tab`() {
        #expect(TelegramMediaSendPermission.allowed.message(for: .stickers) == nil)
        #expect(TelegramMediaSendPermission.restricted.message(for: .stickers) ==
            "You don't have permission to send stickers in this chat.")
        #expect(TelegramMediaSendPermission.restricted.message(for: .gifs) ==
            "You don't have permission to send GIFs in this chat.")
    }

    @Test func `only relevant permission updates trigger a reload`() {
        let matching = Update.updateChatPermissions(.init(
            chatId: 42,
            permissions: TDLibFixtures.permissions(canSendOtherMessages: false),
        ))
        let anotherChat = Update.updateChatPermissions(.init(
            chatId: 43,
            permissions: TDLibFixtures.permissions(canSendOtherMessages: false),
        ))
        let unrelated = Update.updateChatTitle(.init(chatId: 42, title: "Renamed"))

        #expect(TelegramMediaSendPermission.shouldReload(after: matching, chatID: 42))
        #expect(!TelegramMediaSendPermission.shouldReload(after: anotherChat, chatID: 42))
        #expect(!TelegramMediaSendPermission.shouldReload(after: unrelated, chatID: 42))
    }
}
