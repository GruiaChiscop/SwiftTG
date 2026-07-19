// MessageView+ContextMenu.swift

import SwiftUI
import TDLibKit

extension MessageView {
    /// SwiftUI announces actions in reverse declaration order, so declare them from last to first.
    @ViewBuilder var messageAccessibilityActions: some View {
        if customMessage.properties.canBeDeletedOnlyForSelf
            || customMessage.properties.canBeDeletedForAllUsers
        {
            Button("Delete") { showDeleteOptions = true }
        }
        if customMessage.properties.canBePinned {
            Button(customMessage.message.isPinned ? "Unpin" : "Pin", action: togglePinnedMessage)
        }
        if customMessage.properties.canBeEdited {
            Button("Edit", action: edit)
        }
        if customMessage.properties.canBeCopied,
           getFormattedText(from: customMessage.message.content) != nil
        {
            Button("Copy", action: copyMessageText)
        }
        if !reactionChoices.isEmpty {
            Button("React") { showReactionOptions = true }
        }
        if customMessage.properties.canBeReplied {
            Button("Reply", action: reply)
        }
    }

    var contextMenuActions: [ContextMenuAction] {
        var actions = [ContextMenuAction]()

        if customMessage.properties.canBeReplied {
            actions.append(.button(title: "Reply", systemImage: "arrowshape.turn.up.left", action: reply))
        }
        if !reactionChoices.isEmpty {
            actions.append(.menu(
                title: "React",
                systemImage: "face.smiling",
                children: reactionChoices.map { reaction in
                    .button(
                        title: telegramReactionActionTitle(reaction, existing: messageReactions),
                        systemImage: "face.smiling",
                        action: { toggleReaction(reaction) },
                    )
                },
            ))
        }
        if customMessage.properties.canBeCopied,
           getFormattedText(from: customMessage.message.content) != nil
        {
            actions.append(.button(
                title: "Copy",
                systemImage: "rectangle.portrait.on.rectangle.portrait",
                action: copyMessageText,
            ))
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

    var messageReactions: [MessageReaction] {
        customMessage.message.interactionInfo?.reactions?.reactions ?? []
    }

    var reactionChoices: [ReactionType] {
        telegramReactionChoices(existing: messageReactions, available: customMessage.availableReactions)
    }

    func toggleReaction(_ reaction: ReactionType) {
        let service = chatVM.service
        let message = customMessage.message
        Task.background {
            try? await TelegramMessageActions.toggleReaction(
                service: service,
                message: message,
                reaction: reaction,
            )
        }
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
        let message = customMessage.message
        let service = chatVM.service
        Task.background {
            try await TelegramMessageActions.togglePinned(service: service, message: message)
        }
    }

    func copyMessageText() {
        guard let formattedText = getFormattedText(from: customMessage.message.content) else { return }
        UIPasteboard.setFormattedText(formattedText)
    }

    func getFormattedText(from content: MessageContent) -> FormattedText? {
        switch content {
        case .messageText(let messageText):
            guard !messageText.text.text.isEmpty else { return nil }
            return messageText.text
        case .messagePhoto(let messagePhoto):
            guard !messagePhoto.caption.text.isEmpty else { return nil }
            return messagePhoto.caption
        case .messageVideo(let messageVideo):
            guard !messageVideo.caption.text.isEmpty else { return nil }
            return messageVideo.caption
        case .messageVoiceNote(let messageVoiceNote):
            guard !messageVoiceNote.caption.text.isEmpty else { return nil }
            return messageVoiceNote.caption
        case .messageAudio(let messageAudio):
            guard !messageAudio.caption.text.isEmpty else { return nil }
            return messageAudio.caption
        case .messageDocument(let messageDocument):
            guard !messageDocument.caption.text.isEmpty else { return nil }
            return messageDocument.caption
        default:
            return nil
        }
    }
}
