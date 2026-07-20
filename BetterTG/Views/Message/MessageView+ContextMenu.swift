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
           telegramMessageFormattedText(customMessage.message) != nil
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
           telegramMessageFormattedText(customMessage.message) != nil
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
        chatVM.toggleReaction(reaction, on: customMessage.message)
    }

    func reply() {
        chatVM.reply(to: customMessage)
    }

    func edit() {
        chatVM.edit(customMessage)
    }

    func togglePinnedMessage() {
        chatVM.togglePinnedMessage(customMessage.message)
    }

    func copyMessageText() {
        guard let formattedText = telegramMessageFormattedText(customMessage.message) else { return }
        UIPasteboard.setFormattedText(formattedText)
    }
}
