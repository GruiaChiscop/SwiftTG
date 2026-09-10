// TelegramOnlinePresence.swift

import TDLibKit

/// Tells TDLib whether the current user is actively using the app.
///
/// While `true`, TDLib keeps the account marked online server-side - re-sending the presence ping
/// on its own roughly every 30s - and the server streams real-time updates, notably peers'
/// `updateUserStatus`. While `false` the session drops to a power-saving mode where a peer's
/// presence only refreshes as a side effect of other traffic (e.g. sending a message), so an open
/// chat can sit showing a stale "last seen".
///
/// Every real client toggles this on foreground/background transitions: Telegram-iOS via
/// `account.updateStatus(offline:)` (`ManagedAccountPresence`, re-pinged on a 30s timer), Unigram
/// via this exact `setOption("online", …)` on window activation.
func telegramSetOnlinePresence(_ online: Bool, service: any TelegramService) async {
    _ = try? await service.setOption(
        name: "online",
        value: .optionValueBoolean(OptionValueBoolean(value: online)),
    )
}
