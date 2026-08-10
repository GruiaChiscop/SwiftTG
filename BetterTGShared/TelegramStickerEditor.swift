// TelegramStickerEditor.swift

import ImageIO
import SwiftUI
import TDLibKit

struct TelegramStickerEditor: View {
    // MARK: Lifecycle

    init(
        sticker: Sticker,
        service: any TelegramService,
        chatId: Int64,
        actionTitle: String,
        onSave: @escaping @MainActor (Data, String) async throws -> Void,
    ) {
        self.sticker = sticker
        self.service = service
        self.chatId = chatId
        self.actionTitle = actionTitle
        self.onSave = onSave
        _draft = State(initialValue: TelegramStickerCreationDraft(emojis: sticker.emoji))
    }

    // MARK: Internal

    let sticker: Sticker
    let service: any TelegramService
    let chatId: Int64
    let actionTitle: String
    let onSave: @MainActor (Data, String) async throws -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let sourceImage {
                        TelegramStickerEditorPreview(sourceImage: sourceImage, editorState: editorState)

                        TelegramEditorToolbar(
                            editorState: editorState,
                            addText: showTextPrompt,
                            addEmoji: showEmojiPrompt,
                            addSticker: showStickerPicker,
                            addCutout: showCutoutComposer,
                        )

                        TelegramEditorInspector(editorState: editorState)

                        TextField("Sticker Emoji", text: $draft.emojis)
                            .onChange(of: draft.emojis) { _, newValue in
                                let filtered = TelegramStickerCreationDraft.filteredToEmoji(newValue)
                                if filtered != newValue {
                                    draft.emojis = filtered
                                }
                            }
                    } else if errorMessage == nil {
                        ProgressView("Loading sticker")
                            .frame(maxWidth: .infinity, minHeight: 240)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .accessibilityFocused($errorIsFocused)
                    }
                }
                .padding()
            }
            .navigationTitle("Edit Sticker")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", role: .cancel, action: dismissEditor)
                            .disabled(isSaving)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        if isSaving {
                            ProgressView()
                        } else {
                            Button(actionTitle, action: save)
                                .disabled(sourceImage == nil || !draft.isValid)
                        }
                    }
                }
        }
        .task(id: sticker.sticker.id) { await load() }
        .interactiveDismissDisabled(isSaving)
        .onDisappear(perform: cleanupTemporaryCutouts)
        .alert("Add Text", isPresented: $showsTextPrompt) {
            TextField("Text", text: $draftText)
            Button("Add", action: addText)
                .disabled(draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Cancel", role: .cancel) { draftText = "" }
        }
        .alert("Add Emoji", isPresented: $showsEmojiPrompt) {
            TextField("Emoji", text: $draftEmoji)
            Button("Add", action: addEmoji)
                .disabled(draftEmoji.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Cancel", role: .cancel) { draftEmoji = "" }
        }
        .sheet(isPresented: $showsStickerPicker) {
            TelegramEditorStickerPicker(service: service, chatId: chatId, onSelected: addSticker)
        }
        .sheet(isPresented: $showsCutoutComposer) {
            TelegramEditorCutoutComposer(onSelected: addCutout)
        }
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 680)
        #endif
    }

    // MARK: Private

    @AccessibilityFocusState private var errorIsFocused: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var editorState = TelegramMediaEditorState()
    @State private var sourceImage: CGImage?
    @State private var draft: TelegramStickerCreationDraft
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showsTextPrompt = false
    @State private var showsEmojiPrompt = false
    @State private var showsStickerPicker = false
    @State private var showsCutoutComposer = false
    @State private var draftText = ""
    @State private var draftEmoji = ""
    @State private var temporaryCutoutURLs = Set<URL>()

    @MainActor private func load() async {
        errorMessage = nil
        do {
            let file = try await service.downloadFile(
                fileId: sticker.sticker.id,
                limit: 0,
                offset: 0,
                priority: 32,
                synchronous: true,
            )
            guard file.local.isDownloadingCompleted, !file.local.path.isEmpty else {
                throw TelegramStickerEditorError.downloadFailed
            }
            guard let source = CGImageSourceCreateWithURL(URL(filePath: file.local.path) as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else {
                throw TelegramStickerEditorError.imageDecodingFailed
            }
            try Task.checkCancellation()
            sourceImage = image
        } catch is CancellationError {
            return
        } catch {
            await show(error)
        }
    }

    private func save() {
        Task { await saveEditedSticker() }
    }

    @MainActor private func saveEditedSticker() async {
        guard let sourceImage, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil
        errorIsFocused = false
        do {
            let emojis = try draft.validate()
            let pngData = try TelegramStickerEditorRendering.pngData(
                sourceImage: sourceImage,
                snapshot: editorState.snapshot,
            )
            try await onSave(pngData, emojis)
            cleanupTemporaryCutouts()
            dismiss()
        } catch is CancellationError {
            return
        } catch {
            await show(error)
        }
    }

    private func showTextPrompt() {
        draftText = ""
        showsTextPrompt = true
    }

    private func showEmojiPrompt() {
        draftEmoji = ""
        showsEmojiPrompt = true
    }

    private func showStickerPicker() {
        showsStickerPicker = true
    }

    private func showCutoutComposer() {
        showsCutoutComposer = true
    }

    private func addText() {
        editorState.addText(draftText)
        draftText = ""
    }

    private func addEmoji() {
        editorState.addEmoji(draftEmoji)
        draftEmoji = ""
    }

    private func addSticker(_ overlay: TelegramStickerOverlay) {
        guard !overlay.format.isAnimated else {
            Task { await show(TelegramStickerEditorError.animatedOverlayUnsupported) }
            return
        }
        editorState.addSticker(overlay)
    }

    private func addCutout(_ overlay: TelegramStickerOverlay) {
        temporaryCutoutURLs.insert(overlay.url)
        editorState.addSticker(overlay)
    }

    private func dismissEditor() {
        cleanupTemporaryCutouts()
        dismiss()
    }

    private func cleanupTemporaryCutouts() {
        for url in temporaryCutoutURLs {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryCutoutURLs.removeAll()
    }

    @MainActor private func show(_ error: any Swift.Error) async {
        errorMessage = telegramErrorDescription(error)
        await Task.yield()
        errorIsFocused = true
    }
}
