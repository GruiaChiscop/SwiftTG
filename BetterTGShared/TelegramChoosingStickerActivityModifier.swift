// TelegramChoosingStickerActivityModifier.swift

import SwiftUI
import TDLibKit

// MARK: - TelegramChoosingStickerActivityModifier

struct TelegramChoosingStickerActivityModifier: ViewModifier {
    // MARK: Internal

    let service: any TelegramService
    let chatId: Int64
    let topicId: MessageTopic?

    func body(content: Content) -> some View {
        content
            .onScrollPhaseChange { _, phase in
                update(isChoosing: phase.isScrolling)
            }
            .onDisappear {
                update(isChoosing: false)
            }
    }

    // MARK: Private

    @State private var activityTask: Task<Void, Never>?

    private func update(isChoosing: Bool) {
        activityTask?.cancel()
        activityTask = Task {
            guard !Task.isCancelled else { return }
            _ = try? await service.sendChatAction(
                action: isChoosing ? .chatActionChoosingSticker : .chatActionCancel,
                businessConnectionId: nil,
                chatId: chatId,
                topicId: topicId,
            )
        }
    }
}
