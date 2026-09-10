// ChatInfoNavigation.swift

import SwiftUI
import TDLibKit

/// Shared "leave chat info and open another chat" navigation for the chat-info section views.
/// Dismisses synchronously so the tapped row can't fire twice while the chat resolves, then
/// pushes the resolved chat as a fresh screen.
enum ChatInfoNavigation {
    @MainActor static func open(chatId: Int64, dismiss: DismissAction) {
        dismiss()
        Task {
            guard let customChat = await RootVM.shared.getCustomChat(from: chatId) else { return }
            await Task.yield()
            RootVM.shared.navigate(to: .customChat(customChat))
        }
    }

    @MainActor static func open(member sender: MessageSender, dismiss: DismissAction) {
        dismiss()
        Task {
            let customChat: CustomChat? =
                switch sender {
                case .messageSenderUser(let value):
                    await RootVM.shared.getPrivateCustomChat(userId: value.userId)
                case .messageSenderChat(let value):
                    await RootVM.shared.getCustomChat(from: value.chatId)
                }
            guard let customChat else { return }
            await Task.yield()
            RootVM.shared.navigate(to: .customChat(customChat))
        }
    }
}
