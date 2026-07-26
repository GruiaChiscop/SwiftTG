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
        if customMessage.properties.canBeForwarded {
            Button("Forward", action: forward)
        }
        if customMessage.properties.canBeReplied {
            Button("Reply", action: reply)
        }
    }

    @ViewBuilder var messageContextMenu: some View {
        if customMessage.properties.canBeReplied {
            Button(action: reply) {
                Label("Reply", systemImage: "arrowshape.turn.up.left")
            }
        }
        if customMessage.properties.canBeForwarded {
            Button(action: forward) {
                Label("Forward", systemImage: "arrowshape.turn.up.right")
            }
        }
        if !reactionChoices.isEmpty {
            Menu {
                ForEach(reactionChoices, id: \.self) { reaction in
                    Button {
                        toggleReaction(reaction)
                    } label: {
                        Label(
                            telegramReactionActionTitle(reaction, existing: messageReactions),
                            systemImage: "face.smiling",
                        )
                    }
                }
            } label: {
                Label("React", systemImage: "face.smiling")
            }
        }
        if customMessage.properties.canBeCopied,
           telegramMessageFormattedText(customMessage.message) != nil
        {
            Button(action: copyMessageText) {
                Label("Copy", systemImage: "rectangle.portrait.on.rectangle.portrait")
            }
        }
        if customMessage.properties.canBeEdited {
            Button(action: edit) {
                Label("Edit", systemImage: "square.and.pencil")
            }
        }
        if customMessage.properties.canBePinned {
            Button(action: togglePinnedMessage) {
                Label(
                    customMessage.message.isPinned ? "Unpin" : "Pin",
                    systemImage: customMessage.message.isPinned ? "pin.slash" : "pin",
                )
            }
        }
        if customMessage.properties.canBeDeletedOnlyForSelf
            || customMessage.properties.canBeDeletedForAllUsers
        {
            Divider()
            Button(role: .destructive) {
                showDeleteOptions = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
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

    func forward() {
        chatVM.forward(customMessage)
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
