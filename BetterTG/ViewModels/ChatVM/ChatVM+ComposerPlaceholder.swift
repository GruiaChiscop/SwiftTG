// ChatVM+ComposerPlaceholder.swift

import Combine
import Foundation
@preconcurrency import TDLibKit

extension ChatVM {
    /// Seeds `composerPlaceholder` from the chat snapshot and keeps it live - `customChat.chat`/
    /// `.type` never get updated in place after this `ChatVM` is created, so a live admin-rights
    /// or silent-broadcast change has to be applied here directly rather than by re-reading them.
    func startComposerPlaceholderObservation() {
        refreshComposerPlaceholder()
        guard let supergroupId = customChat.supergroup?.id else { return }
        let chatId = customChat.chat.id
        service.updatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] update in
                Task { @MainActor in
                    self?.applyComposerPlaceholderUpdate(update, supergroupId: supergroupId, chatId: chatId)
                }
            }
            .store(in: &cancellables)
    }

    private func refreshComposerPlaceholder() {
        composerPlaceholder = telegramComposerPlaceholder(
            isChannel: customChat.supergroup?.isChannel ?? false,
            defaultDisableNotification: customChat.chat.defaultDisableNotification,
            status: customChat.supergroup?.status,
        )
    }

    @MainActor private func applyComposerPlaceholderUpdate(_ update: Update, supergroupId: Int64, chatId: Int64) {
        switch update {
        case .updateSupergroup(let value) where value.supergroup.id == supergroupId:
            composerPlaceholder = telegramComposerPlaceholder(
                isChannel: value.supergroup.isChannel,
                defaultDisableNotification: customChat.chat.defaultDisableNotification,
                status: value.supergroup.status,
            )
        case .updateChatDefaultDisableNotification(let value) where value.chatId == chatId:
            composerPlaceholder = telegramComposerPlaceholder(
                isChannel: customChat.supergroup?.isChannel ?? false,
                defaultDisableNotification: value.defaultDisableNotification,
                status: customChat.supergroup?.status,
            )
        default:
            break
        }
    }
}
