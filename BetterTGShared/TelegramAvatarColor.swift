// TelegramAvatarColor.swift

import SwiftUI

extension Color {
    /// Matches Telegram's classic avatar-color hashing (a deterministic per-id palette index) so a
    /// given chat gets the same color everywhere - `id` accepts either a user id or a chat id;
    /// supergroup/channel chat ids carry a `-100` marker prefix that gets stripped first so they
    /// hash the same way official clients hash the underlying peer id.
    init(telegramAvatarId id: Int64) {
        let colors: [Color] = [.red, .green, .yellow, .blue, .purple, .pink, .blue, .orange]
        let normalizedId = abs(Int(String(id).replacing("-100", with: "")) ?? 0)
        self = colors[[0, 7, 4, 1, 6, 3, 5][normalizedId % 7]]
    }
}
