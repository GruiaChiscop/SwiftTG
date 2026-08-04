// MacSessionModel+ChatListMetadata.swift

import TDLibKit

extension MacSessionModel {
    /// Resolves the identity badge (Premium/Verified/Scam/Fake) for a private or secret chat's
    /// peer, caching the result so it's only resolved once per chat - `ChatListItemState` (unlike
    /// iOS's `CustomChat`) doesn't carry the peer `User` itself, only its `userId`. Never shows a
    /// badge on the user's own chat entry, mirroring Unigram's `IdentityIcon` behavior.
    func loadIdentityBadge(for chat: ChatListItemState) async {
        guard chatIdentityBadges[chat.chatId] == nil, let userId = chat.userId else { return }
        guard let user = try? await service.getUser(userId: userId) else { return }
        let currentUserId = await TelegramCurrentUserCache.shared.userId(service: service)
        chatIdentityBadges[chat.chatId] = userId == currentUserId ? nil : user.identityBadge
    }
}
