// RootVM+DeepLink.swift

import SwiftUI
@preconcurrency import TDLibKit

extension RootVM {
    /// Entry point for both `t.me`/`telegram.me` links tapped inside message text and `tg:`/`t.me`
    /// URLs the app was opened with (`.onOpenURL`). Only ever attempts TDLib resolution for links
    /// `TelegramDeepLink.isTelegramLink` recognizes - anything else (a plain https link in a
    /// message, for instance) goes straight to the system browser, matching normal `Text` link
    /// behavior.
    func handleDeepLink(_ url: URL) {
        guard TelegramDeepLink.isTelegramLink(url) else {
            UIApplication.shared.open(url)
            return
        }
        Task {
            let action = await TelegramDeepLink.resolve(url, service: service)
            await applyDeepLinkAction(action)
        }
    }

    func confirmPendingDeepLinkJoin() {
        guard let pending = pendingDeepLinkJoin else { return }
        pendingDeepLinkJoin = nil
        Task {
            guard let chatId = await TelegramDeepLink.join(inviteLink: pending.inviteLink, service: service) else {
                deepLinkErrorMessage = "Couldn't join this chat."
                return
            }
            await openDeepLinkChat(chatId: chatId, messageId: nil)
        }
    }

    @MainActor private func applyDeepLinkAction(_ action: TelegramDeepLinkAction) async {
        switch action {
        case .openChat(let chatId, let messageId):
            await openDeepLinkChat(chatId: chatId, messageId: messageId)
        case .confirmJoin(let info, let inviteLink):
            pendingDeepLinkJoin = TelegramPendingDeepLinkJoin(info: info, inviteLink: inviteLink)
        case .addProxy(let proxy):
            await addDeepLinkProxy(proxy)
        case .openExternally(let url):
            await UIApplication.shared.open(url)
        case .unsupported:
            deepLinkErrorMessage = "This link isn't supported yet."
        }
    }

    @MainActor private func openDeepLinkChat(chatId: Int64, messageId: Int64?) async {
        guard let customChat = await getCustomChat(from: chatId) else {
            deepLinkErrorMessage = "This chat couldn't be opened."
            return
        }
        navigate(to: .customChat(customChat, messageId: messageId))
    }

    @MainActor private func addDeepLinkProxy(_ proxy: Proxy) async {
        do {
            _ = try await service.addProxy(comment: nil, enable: true, proxy: proxy)
        } catch {
            deepLinkErrorMessage = "Couldn't add this proxy."
        }
    }
}
