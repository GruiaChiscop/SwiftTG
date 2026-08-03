// MacSessionModel+ComposerInput.swift

import AppKit
import TDLibKit
import UniformTypeIdentifiers

extension MacSessionModel {
    var activeLinkPreviewComposer: TelegramLinkPreviewComposer {
        editingMessage == nil ? linkPreviewComposer : editLinkPreviewComposer
    }

    func submitComposer(schedulingState: MessageSchedulingState? = nil) {
        guard !isSubmittingMessage else { return }
        if !selectedDocumentURLs.isEmpty, editingMessage == nil {
            sendSelectedDocuments(schedulingState: schedulingState)
        } else if !selectedPhotoURLs.isEmpty, editingMessage == nil {
            sendSelectedPhotos(schedulingState: schedulingState)
        } else if editingMessage != nil {
            editMessage()
        } else {
            sendTextMessage(schedulingState: schedulingState)
        }
    }

    func choosePhotos() {
        guard !isRecordingVoice, editingMessage == nil else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose Photos"
        panel.prompt = "Attach"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK else { return }
        selectedDocumentURLs = []
        selectedPhotoURLs = panel.urls
    }

    func chooseDocuments() {
        guard !isRecordingVoice, editingMessage == nil else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose Files"
        panel.prompt = "Attach"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.item]
        guard panel.runModal() == .OK else { return }
        selectedPhotoURLs = []
        selectedDocumentURLs = panel.urls
    }

    /// Unlike `choosePhotos()`, adds to whatever's already selected instead of replacing it - for
    /// picking more photos from the attachment review screen, where the existing selection must
    /// survive.
    func addPhotos() {
        guard !isRecordingVoice, editingMessage == nil else { return }
        let panel = NSOpenPanel()
        panel.title = "Add Photos"
        panel.prompt = "Add"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK else { return }
        selectedPhotoURLs.append(contentsOf: panel.urls)
    }

    /// Unlike `chooseDocuments()`, adds to whatever's already selected instead of replacing it.
    func addDocuments() {
        guard !isRecordingVoice, editingMessage == nil else { return }
        let panel = NSOpenPanel()
        panel.title = "Add Files"
        panel.prompt = "Add"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.item]
        guard panel.runModal() == .OK else { return }
        selectedDocumentURLs.append(contentsOf: panel.urls)
    }

    @discardableResult func attachPastedFiles(_ urls: [URL]) -> Bool {
        guard !isRecordingVoice, editingMessage == nil else { return false }
        let pastedFiles = urls.filter { url in
            guard url.isFileURL else { return false }
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
                && !isDirectory.boolValue
        }
        guard !pastedFiles.isEmpty else { return false }

        var seenURLs = Set<URL>()
        let combined = (selectedPhotoURLs + selectedDocumentURLs + pastedFiles).filter {
            seenURLs.insert($0).inserted
        }
        if combined.allSatisfy(isImageAttachment) {
            selectedDocumentURLs = []
            selectedPhotoURLs = combined
        } else {
            selectedPhotoURLs = []
            selectedDocumentURLs = combined
        }
        return true
    }

    func removeSelectedDocument(_ url: URL) {
        selectedDocumentURLs.removeAll { $0 == url }
    }

    func removeSelectedPhoto(_ url: URL) {
        selectedPhotoURLs.removeAll { $0 == url }
    }

    func beginReply(to message: Message) {
        draftReplyLoadTask?.cancel()
        draftReplyLoadTask = nil
        editingMessage = nil
        editMessageText = NSAttributedString(string: "")
        replyingToMessage = message
    }

    func cancelReplyOrEdit() {
        draftReplyLoadTask?.cancel()
        draftReplyLoadTask = nil
        editingMessage = nil
        replyingToMessage = nil
        editMessageText = NSAttributedString(string: "")
        editLinkPreviewComposer.configure(preview: nil, options: nil)
    }

    func beginEditing(_ message: Message) {
        guard let text = TelegramMessageEditing.editableFormattedText(from: message) else { return }
        selectedPhotoURLs = []
        selectedDocumentURLs = []
        replyingToMessage = nil
        editLinkPreviewComposer.configure(
            preview: telegramMessageLinkPreview(message),
            options: telegramMessageLinkPreviewOptions(message),
        )
        editingMessage = message
        editMessageText = macComposerAttributedString(text)
    }

    func saveCurrentDraft() {
        guard editingMessage == nil, let chatId = openedChatId else { return }
        let draft = TelegramDrafts.make(
            formattedText: macComposerFormattedText(messageText),
            replyMessageId: replyingToMessage?.id,
            linkPreviewOptions: linkPreviewComposer.options,
        )
        let service = service
        Task {
            _ = try? await service.setChatDraftMessage(
                chatId: chatId,
                draftMessage: draft,
                topicId: nil,
            )
        }
    }

    // MARK: Internal (called from `+MessageSending.swift`/`+VoiceRecording.swift`, different files)

    func clearDraft(chatId: Int64) {
        let service = service
        Task {
            _ = try? await service.setChatDraftMessage(
                chatId: chatId,
                draftMessage: nil,
                topicId: nil,
            )
        }
    }

    // MARK: Internal (called from `+ChatActivation.swift`, a different file)

    func restoreDraft(_ draft: DraftMessage?, chatId: Int64) {
        draftReplyLoadTask?.cancel()
        draftReplyLoadTask = nil
        let linkPreviewOptions: LinkPreviewOptions? =
            if let draft, case .draftMessageContentText(let content) = draft.content {
                content.linkPreviewOptions
            } else {
                nil
            }
        linkPreviewComposer.configure(preview: nil, options: linkPreviewOptions)
        messageText = TelegramDrafts.formattedText(from: draft)
            .map(macComposerAttributedString)
            ?? NSAttributedString(string: "")
        replyingToMessage = nil

        guard let replyMessageId = TelegramDrafts.replyMessageId(from: draft) else { return }
        let service = service
        draftReplyLoadTask = Task { [weak self] in
            let message = try? await service.getMessage(chatId: chatId, messageId: replyMessageId)
            guard !Task.isCancelled,
                  let self,
                  openedChatId == chatId,
                  replyingToMessage == nil
            else { return }
            replyingToMessage = message
            draftReplyLoadTask = nil
        }
    }
}
