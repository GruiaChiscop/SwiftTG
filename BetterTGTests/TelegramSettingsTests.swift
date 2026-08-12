// TelegramSettingsTests.swift

@testable import BetterTG
import TDLibKit
import Testing

struct TelegramSettingsTests {
    // MARK: Internal

    @Test func `proxy shortcut follows Telegram visibility and status`() {
        #expect(TelegramProxyShortcutStatus.resolve(proxies: []) == nil)

        let disabledProxy = makeProxy(id: 1, isEnabled: false, type: .proxyTypeSocks5(.init(
            password: "",
            username: "",
        )))
        #expect(TelegramProxyShortcutStatus.resolve(proxies: [disabledProxy])?.value == "Disabled")

        let enabledProxy = makeProxy(id: 2, isEnabled: true, type: .proxyTypeHttp(.init(
            httpOnly: false,
            password: "",
            username: "",
        )))
        #expect(TelegramProxyShortcutStatus.resolve(proxies: [disabledProxy, enabledProxy])?.value == "HTTP")
    }

    @Test func `privacy base option is found after exceptions`() {
        let rules = UserPrivacySettingRules(rules: [
            .userPrivacySettingRuleAllowUsers(.init(userIds: [10])),
            .userPrivacySettingRuleRestrictUsers(.init(userIds: [20])),
            .userPrivacySettingRuleAllowContacts,
            .userPrivacySettingRuleRestrictAll,
        ])

        #expect(TelegramPrivacyOption(rules: rules) == .myContacts)
        #expect(TelegramPrivacyRules.alwaysAllowUserIds(in: rules) == [10])
        #expect(TelegramPrivacyRules.neverAllowUserIds(in: rules) == [20])
    }

    @Test func `changing privacy base preserves every exception`() {
        let groupRule = UserPrivacySettingRule.userPrivacySettingRuleAllowChatMembers(.init(chatIds: [30]))
        let rules = UserPrivacySettingRules(rules: [
            .userPrivacySettingRuleAllowUsers(.init(userIds: [10])),
            .userPrivacySettingRuleRestrictUsers(.init(userIds: [20])),
            groupRule,
            .userPrivacySettingRuleAllowPremiumUsers,
            .userPrivacySettingRuleAllowContacts,
            .userPrivacySettingRuleRestrictAll,
        ])

        let updated = TelegramPrivacyRules.replacingBaseOption(in: rules, with: .everybody)

        #expect(TelegramPrivacyOption(rules: updated) == .everybody)
        #expect(TelegramPrivacyRules.alwaysAllowUserIds(in: updated) == [10])
        #expect(TelegramPrivacyRules.neverAllowUserIds(in: updated) == [20])
        #expect(TelegramPrivacyRules.alwaysAllowChatIds(in: updated) == [30])
        #expect(updated.rules.contains(groupRule))
        #expect(updated.rules.contains(.userPrivacySettingRuleAllowPremiumUsers))
    }

    @Test func `privacy user cannot be in both exception lists`() {
        let rules = UserPrivacySettingRules(rules: [.userPrivacySettingRuleRestrictAll])
        let updated = TelegramPrivacyRules.replacingUserExceptions(
            in: rules,
            alwaysAllow: [10, 20],
            neverAllow: [20, 30],
            alwaysAllowChatIds: [40, 50],
            neverAllowChatIds: [50, 60],
        )

        #expect(TelegramPrivacyRules.alwaysAllowUserIds(in: updated) == [10, 20])
        #expect(TelegramPrivacyRules.neverAllowUserIds(in: updated) == [30])
        #expect(TelegramPrivacyRules.alwaysAllowChatIds(in: updated) == [40, 50])
        #expect(TelegramPrivacyRules.neverAllowChatIds(in: updated) == [60])
    }

    @Test func `changing privacy base preserves rules SwiftTG cannot regenerate`() {
        let rules = UserPrivacySettingRules(rules: [
            .userPrivacySettingRuleRestrictContacts,
            .userPrivacySettingRuleAllowAll,
        ])

        let updated = TelegramPrivacyRules.replacingBaseOption(in: rules, with: .nobody)

        #expect(updated.rules.contains(.userPrivacySettingRuleRestrictContacts))
    }

    @Test func `account deletion period accepts server day values`() {
        #expect(TelegramAccountDeletionPeriod(days: 30) == .oneMonth)
        #expect(TelegramAccountDeletionPeriod(days: 365) == .oneYear)
        #expect(TelegramAccountDeletionPeriod(days: 730) == .twoYears)
    }

    @Test func `incoming message privacy maps every TDLib mode`() {
        let everybody = NewChatPrivacySettings(
            allowNewChatsFromUnknownUsers: true,
            incomingPaidMessageStarCount: 0,
        )
        let contacts = NewChatPrivacySettings(
            allowNewChatsFromUnknownUsers: false,
            incomingPaidMessageStarCount: 0,
        )
        let paid = NewChatPrivacySettings(
            allowNewChatsFromUnknownUsers: true,
            incomingPaidMessageStarCount: 25,
        )

        #expect(TelegramIncomingMessagePrivacyMode(settings: everybody) == .everybody)
        #expect(TelegramIncomingMessagePrivacyMode(settings: contacts) == .contactsAndPremium)
        #expect(TelegramIncomingMessagePrivacyMode(settings: paid) == .paidMessages)
        #expect(TelegramIncomingMessagePrivacyMode.paidMessages.settings(paidStars: 25) == paid)
    }

    // MARK: Private

    private func makeProxy(id: Int, isEnabled: Bool, type: ProxyType) -> AddedProxy {
        AddedProxy(
            comment: "",
            id: id,
            isEnabled: isEnabled,
            lastUsedDate: 0,
            proxy: Proxy(port: 443, server: "proxy.example", type: type),
        )
    }
}
