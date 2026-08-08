// TelegramDeepLink.swift

import Foundation
@preconcurrency import TDLibKit

// MARK: - TelegramPendingDeepLinkJoin

/// Wraps a `.confirmJoin` deep-link action into something a SwiftUI alert can bind to - shared by
/// both platforms' own deep-link handling (`RootVM+DeepLink.swift` on iOS,
/// `MacSessionModel+DeepLink.swift` on macOS).
struct TelegramPendingDeepLinkJoin: Identifiable {
    let info: ChatInviteLinkInfo
    let inviteLink: String

    var id: String { inviteLink }
}

// MARK: - TelegramDeepLinkAction

/// What a resolved link means for the app to do next - kept separate from the actual navigation,
/// since that differs per platform (`RootVM.navigate` on iOS, `MacSessionModel.activateChat` on
/// macOS).
enum TelegramDeepLinkAction {
    case openChat(chatId: Int64, messageId: Int64?)
    /// TDLib already resolved the invite to a chat the user isn't a member of yet - show a
    /// confirmation before actually joining, per `InternalLinkTypeChatInvite`'s own doc comment.
    case confirmJoin(ChatInviteLinkInfo, inviteLink: String)
    case addProxy(Proxy)
    case openExternally(URL)
    case unsupported
}

// MARK: - TelegramDeepLink

/// Resolves `t.me`/`telegram.me` links and `tg:` deep links the way the official app does, via
/// TDLib's own `getInternalLinkType` - it already knows every link shape Telegram has ever shipped
/// (public chats, invites, message links, phone-number links, bot start parameters, proxies, and
/// many Premium/gift/story kinds this app doesn't have screens for). Unhandled cases fall back to
/// `.unsupported` rather than guessing.
enum TelegramDeepLink {
    /// True for any URL this app should try to resolve itself before falling through to the
    /// system browser. `t.me`/`telegram.me` are Telegram's own web domains; `tg:` is the scheme
    /// every Telegram client (including this one) registers for cross-app deep linking. Universal
    /// Links for `t.me` itself aren't something a third-party app can register for - that requires
    /// an apple-app-site-association file hosted by the domain owner, which is Telegram, not us -
    /// so this only ever sees a `t.me` URL when it reaches the app some other way (a link tapped
    /// inside our own message text, the share sheet, or an explicit `tg:` open).
    static func isTelegramLink(_ url: URL) -> Bool {
        if url.scheme?.lowercased() == "tg" {
            return true
        }
        guard let host = url.host?.lowercased() else { return false }
        return host == "t.me" || host == "telegram.me" || host.hasSuffix(".t.me")
    }

    static func resolve(_ url: URL, service: any TelegramService) async -> TelegramDeepLinkAction {
        guard let type = try? await service.getInternalLinkType(link: url.absoluteString) else {
            return isTelegramLink(url) ? .unsupported : .openExternally(url)
        }

        switch type {
        case .internalLinkTypePublicChat(let value):
            guard let chat = try? await service.searchPublicChat(username: value.chatUsername) else {
                return .unsupported
            }
            return .openChat(chatId: chat.id, messageId: nil)

        case .internalLinkTypeChatInvite(let value):
            guard let info = try? await service.checkChatInviteLink(inviteLink: value.inviteLink) else {
                return .unsupported
            }
            // Non-zero chatId means the user already has access (already a member, or it's a
            // public chat visible without joining) - just open it, no need to join again.
            guard info.chatId != 0 else {
                return .confirmJoin(info, inviteLink: value.inviteLink)
            }
            return .openChat(chatId: info.chatId, messageId: nil)

        case .internalLinkTypeMessage(let value):
            guard let info = try? await service.getMessageLinkInfo(url: value.url), info.chatId != 0 else {
                return .unsupported
            }
            return .openChat(chatId: info.chatId, messageId: info.message?.id)

        case .internalLinkTypeUserPhoneNumber(let value):
            guard
                let user = try? await service.searchUserByPhoneNumber(
                    onlyLocal: false,
                    phoneNumber: value.phoneNumber,
                ),
                let chat = try? await service.createPrivateChat(force: false, userId: user.id)
            else { return .unsupported }
            return .openChat(chatId: chat.id, messageId: nil)

        case .internalLinkTypeBotStart(let value):
            guard let botChat = try? await service.searchPublicChat(username: value.botUsername) else {
                return .unsupported
            }
            if value.autostart {
                _ = try? await service.sendBotStartMessage(
                    botUserId: botChat.id,
                    chatId: botChat.id,
                    parameter: value.startParameter,
                )
            }
            return .openChat(chatId: botChat.id, messageId: nil)

        case .internalLinkTypeProxy(let value):
            guard let proxy = value.proxy else { return .unsupported }
            return .addProxy(proxy)

        default:
            return .unsupported
        }
    }

    /// Completes a join started by a `.confirmJoin` action, returning the chat id to open once
    /// the user has confirmed.
    static func join(inviteLink: String, service: any TelegramService) async -> Int64? {
        guard let result = try? await service.joinChatByInviteLink(inviteLink: inviteLink) else { return nil }
        guard case .chatJoinResultSuccess(let value) = result else { return nil }
        return value.chatId
    }
}
