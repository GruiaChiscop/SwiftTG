// ChatInfoUnofficialAppWarningSection.swift

import SwiftUI

struct ChatInfoUnofficialAppWarningSection: View {
    let info: TelegramChatInfoData

    var body: some View {
        if info.usesUnofficialApp {
            Section {
                Label(
                    "Telegram reports that this user uses an unofficial app that may pose a security risk.",
                    systemImage: "exclamationmark.triangle",
                )
                .foregroundStyle(.orange)
            }
        }
    }
}
