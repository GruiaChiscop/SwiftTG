import SwiftUI
import TDLibKit

extension MessageView {
    var contextMenuActions: [ContextMenuAction] {
        var actions = [ContextMenuAction]()

        if customMessage.properties.canBeReplied {
            actions.append(.button(title: "Reply", systemImage: "arrowshape.turn.up.left", action: reply))
        }
        if customMessage.canReact {
            actions.append(.button(title: "React", systemImage: "heart") {
                Task.background {
                    try? await td.addMessageReaction(
                        chatId: chatVM.customChat.chat.id,
                        isBig: false,
                        messageId: customMessage.id,
                        reactionType: .reactionTypeEmoji(.init(emoji: "❤")),
                        updateRecentReactions: true,
                    )
                }
            })
        }
        if customMessage.properties.canBeCopied,
           let formattedText = getFormattedText(from: customMessage.message.content)
        {
            actions.append(.button(title: "Copy", systemImage: "rectangle.portrait.on.rectangle.portrait") {
                UIPasteboard.setFormattedText(formattedText)
            })
        }
        if customMessage.properties.canBeEdited {
            actions.append(.button(title: "Edit", systemImage: "square.and.pencil", action: edit))
        }
        if customMessage.properties.canBePinned {
            actions.append(.button(
                title: customMessage.message.isPinned ? "Unpin" : "Pin",
                systemImage: customMessage.message.isPinned ? "pin.slash" : "pin",
                action: togglePinnedMessage,
            ))
        }
        if customMessage.properties.canBeDeletedOnlyForSelf
            || customMessage.properties.canBeDeletedForAllUsers
        {
            actions.append(.divider)
            actions.append(.button(title: "Delete", systemImage: "trash", attributes: .destructive) {
                showDeleteOptions = true
            })
        }
        return actions
    }

    func reply() {
        if chatVM.replyMessage != nil {
            withAnimation { chatVM.replyMessage = nil }
            Task.main(delay: 0.4) {
                withAnimation { chatVM.replyMessage = customMessage }
            }
        } else {
            withAnimation { chatVM.replyMessage = customMessage }
        }
    }

    func edit() {
        if chatVM.editCustomMessage != nil {
            withAnimation { chatVM.editCustomMessage = nil }
            Task.main(delay: 0.4) {
                withAnimation { chatVM.editCustomMessage = customMessage }
            }
        } else {
            withAnimation { chatVM.editCustomMessage = customMessage }
        }
    }

    func togglePinnedMessage() {
        Task.background {
            if customMessage.message.isPinned {
                try await td.unpinChatMessage(
                    chatId: chatVM.customChat.chat.id,
                    messageId: customMessage.id,
                )
            } else {
                try await td.pinChatMessage(
                    chatId: chatVM.customChat.chat.id,
                    disableNotification: false,
                    messageId: customMessage.id,
                    onlyForSelf: false,
                )
            }
        }
    }

    func getFormattedText(from content: MessageContent) -> FormattedText? {
        switch content {
        case .messageText(let messageText):
            guard !messageText.text.text.isEmpty else { return nil }
            return messageText.text
        case .messagePhoto(let messagePhoto):
            guard !messagePhoto.caption.text.isEmpty else { return nil }
            return messagePhoto.caption
        case .messageVoiceNote(let messageVoiceNote):
            guard !messageVoiceNote.caption.text.isEmpty else { return nil }
            return messageVoiceNote.caption
        default:
            return nil
        }
    }
}
