// MessageView+ContextMenu.swift

import SwiftUI
import TDLibKit

extension MessageView {
    var reactionPicker: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    ForEach(reactionChoices, id: \.self) { reaction in
                        let isSelected = messageReactions.contains {
                            $0.type == reaction && $0.isChosen
                        }
                        Button {
                            toggleReaction(reaction)
                            showReactionOptions = false
                        } label: {
                            Text(telegramReactionSymbol(reaction))
                                .font(.title2)
                                .frame(width: 44, height: 44)
                                .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
                                .clipShape(.circle)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
                .padding(8)
            }
            .scrollIndicators(.hidden)
            .frame(height: 60)

            Divider()

            Button("Dismiss", role: .cancel) {
                showReactionOptions = false
            }
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .frame(width: max(140, min(CGFloat(reactionChoices.count) * 48 + 16, 320)))
    }

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
        if canTranslate {
            Button(customMessage.showsTranslation ? "Show Original" : "Translate", action: toggleTranslation)
        }
        if customMessage.messageDocument != nil {
            Button("Save to Files", action: saveDocument)
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
        if canTranslate {
            Button(action: toggleTranslation) {
                Label(
                    customMessage.showsTranslation ? "Show Original" : "Translate",
                    systemImage: "character.bubble",
                )
            }
            .disabled(customMessage.isTranslating)
        }
        if customMessage.messageDocument != nil {
            Button(action: saveDocument) {
                Label("Save to Files", systemImage: "folder")
            }
            .disabled(isSavingDocument)
        }
        if customMessage.messageContact != nil {
            Button(action: activateContact) {
                Label(contactActionTitle, systemImage: contactActionSystemImage)
            }
            .disabled(isAddingContact)
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

    var canTranslate: Bool {
        customMessage.canBeTranslated
    }

    var contactActionTitle: String {
        guard let messageContact = customMessage.messageContact else { return "" }
        return TelegramContactPresentation(messageContact).hasTelegramAccount ? "Message" : "Add to Contacts"
    }

    var contactActionSystemImage: String {
        guard let messageContact = customMessage.messageContact else { return "" }
        return TelegramContactPresentation(messageContact).hasTelegramAccount
            ? "message"
            : "person.crop.circle.badge.plus"
    }

    func toggleTranslation() {
        chatVM.toggleTranslation(customMessage)
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

    func activateContact() {
        guard let messageContact = customMessage.messageContact else { return }
        let presentation = TelegramContactPresentation(messageContact)
        if presentation.hasTelegramAccount {
            chatVM.navigateToContact(userId: presentation.userId)
        } else {
            addSharedContact(presentation)
        }
    }

    func activateLocation() {
        guard let messageLocation = customMessage.messageLocation else { return }
        let latitude = messageLocation.location.latitude
        let longitude = messageLocation.location.longitude
        guard let url = URL(string: "http://maps.apple.com/?ll=\(latitude),\(longitude)") else { return }
        UIApplication.shared.open(url)
    }

    func addSharedContact(_ presentation: TelegramContactPresentation) {
        guard !isAddingContact else { return }
        isAddingContact = true
        chatVM.messageActionError = nil

        Task { @MainActor in
            defer { isAddingContact = false }
            do {
                let imported = ImportedContact(
                    firstName: presentation.firstName,
                    lastName: presentation.lastName,
                    note: nil,
                    phoneNumber: presentation.phoneNumber,
                )
                let result = try await chatVM.service.importContacts(contacts: [imported])
                guard result.userIds.first.map({ $0 != 0 }) == true else {
                    chatVM.messageActionError = "No Telegram account was found for this phone number."
                    return
                }
                UIAccessibility.post(notification: .announcement, argument: "Added to Contacts")
            } catch {
                guard !Task.isCancelled else { return }
                chatVM.messageActionError = "Contact couldn't be added: \(telegramErrorDescription(error))"
            }
        }
    }

    func saveDocument() {
        guard !isSavingDocument, let messageDocument = customMessage.messageDocument else { return }
        isSavingDocument = true
        chatVM.messageActionError = nil

        Task { @MainActor in
            defer { isSavingDocument = false }
            do {
                let file = try await chatVM.service.downloadFile(
                    fileId: messageDocument.document.document.id,
                    limit: 0,
                    offset: 0,
                    priority: 24,
                    synchronous: true,
                )
                guard file.local.isDownloadingCompleted, !file.local.path.isEmpty else {
                    throw TelegramFileTransferError.sourceUnavailable
                }
                let exportURL = try await TelegramDocumentExport.exportURL(
                    sourceURL: URL(filePath: file.local.path),
                    suggestedFileName: messageDocument.document.fileName,
                    identifier: String(customMessage.id),
                )
                showDocumentExporter(exportURL)
            } catch {
                guard !Task.isCancelled else { return }
                chatVM.messageActionError = "File couldn't be saved: \(telegramErrorDescription(error))"
            }
        }
    }
}
