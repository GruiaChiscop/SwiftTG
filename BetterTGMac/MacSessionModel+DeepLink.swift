// MacSessionModel+DeepLink.swift

import AppKit
@preconcurrency import TDLibKit

extension MacSessionModel {
    /// Entry point for both `t.me`/`telegram.me` links clicked inside message text and `tg:`/`t.me`
    /// URLs the app was opened with directly. Mirrors `RootVM+DeepLink.swift` on iOS.
    func handleDeepLink(_ url: URL) {
        guard TelegramDeepLink.isTelegramLink(url) else {
            NSWorkspace.shared.open(url)
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
            activateChat(chatId)
        }
    }

    @MainActor private func applyDeepLinkAction(_ action: TelegramDeepLinkAction) async {
        switch action {
        case .openChat(let chatId, let messageId):
            activateChat(chatId, messageId: messageId)
        case .confirmJoin(let info, let inviteLink):
            pendingDeepLinkJoin = TelegramPendingDeepLinkJoin(info: info, inviteLink: inviteLink)
        case .confirmGroupCallJoin:
            deepLinkErrorMessage = "Group calls aren't supported on macOS yet."
        case .addProxy(let proxy):
            do {
                _ = try await service.addProxy(comment: nil, enable: true, proxy: proxy)
            } catch {
                deepLinkErrorMessage = "Couldn't add this proxy."
            }
        case .openExternally(let url):
            NSWorkspace.shared.open(url)
        case .unsupported:
            deepLinkErrorMessage = "This link isn't supported yet."
        }
    }
}
