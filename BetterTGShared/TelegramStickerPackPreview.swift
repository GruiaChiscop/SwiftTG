// TelegramStickerPackPreview.swift

import SwiftUI
import TDLibKit

struct TelegramStickerPackPreview<Preview: View>: View {
    // MARK: Internal

    let reference: TelegramStickerPackReference
    let service: any TelegramService
    let chatId: Int64
    let onSelect: (Sticker) -> Void
    let preview: (Sticker) -> Preview

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Group {
                    if let stickerSet {
                        ScrollView {
                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 76, maximum: 96), spacing: 12)],
                                spacing: 12,
                            ) {
                                ForEach(stickerSet.stickers, id: \.sticker.id) { sticker in
                                    stickerButton(sticker, stickerSet: stickerSet)
                                }
                            }
                            .padding()
                        }
                    } else if let loadErrorMessage {
                        ContentUnavailableView(
                            "Sticker Pack Unavailable",
                            systemImage: "exclamationmark.triangle",
                            description: Text(loadErrorMessage),
                        )
                        .accessibilityFocused($loadErrorIsFocused)
                    } else {
                        ProgressView("Loading sticker pack")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                installationControls
            }
            .navigationTitle(stickerSet?.title ?? "Sticker Pack")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: dismiss.callAsFunction)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 480)
        #endif
        .task(id: reference.id) { await loadStickerSet() }
        .task(id: pendingInstallationAction) { await changeInstallationState() }
        .sheet(item: $stickerToEdit) { sticker in
            if let stickerSet {
                TelegramStickerEditor(
                    sticker: sticker,
                    service: service,
                    chatId: chatId,
                    actionTitle: "Save",
                    onSave: { output, emojis in
                        try await TelegramStickerEditing.replaceSticker(
                            sticker,
                            inPackNamed: stickerSet.name,
                            output: output,
                            emojis: emojis,
                            service: service,
                        )
                        await loadStickerSet(clearsExisting: false)
                    },
                )
            }
        }
    }

    // MARK: Private

    @AccessibilityFocusState private var loadErrorIsFocused: Bool
    @AccessibilityFocusState private var installationErrorIsFocused: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var stickerSet: StickerSet?
    @State private var isInstalled: Bool?
    @State private var loadErrorMessage: String?
    @State private var installationErrorMessage: String?
    @State private var pendingInstallationAction: TelegramStickerPackInstallationAction?
    @State private var stickerToEdit: Sticker?

    private var installationAction: TelegramStickerPackInstallationAction? {
        guard let stickerSet else { return nil }
        return TelegramStickerPackInstallationAction(
            isInstalled: isInstalled ?? stickerSet.isInstalled,
            isOwned: stickerSet.isOwned,
            stickerCount: stickerSet.stickers.count,
        )
    }

    @ViewBuilder private var installationControls: some View {
        if let installationAction {
            Divider()
            VStack(spacing: 8) {
                Button(role: installationAction.installs ? nil : .destructive) {
                    installationErrorMessage = nil
                    pendingInstallationAction = installationAction
                } label: {
                    HStack {
                        if pendingInstallationAction != nil {
                            ProgressView()
                                .accessibilityHidden(true)
                        }
                        Text(installationAction.title)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(installationAction.installs ? Color.accentColor : Color.red)
                .disabled(pendingInstallationAction != nil)

                if let installationErrorMessage {
                    Text(installationErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .accessibilityFocused($installationErrorIsFocused)
                }
            }
            .padding()
        }
    }

    @ViewBuilder private func stickerButton(_ sticker: Sticker, stickerSet: StickerSet) -> some View {
        let presentation = TelegramStickerPresentation(sticker)
        let canEdit = stickerSet.isOwned && presentation.isEditable
        let button = Button {
            onSelect(sticker)
            dismiss()
        } label: {
            preview(sticker)
                .accessibilityHidden(true)
                .frame(minHeight: 76)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(presentation.pickerAccessibilityLabel(packTitle: stickerSet.title))
        .contextMenu {
            if canEdit {
                Button("Edit Sticker", systemImage: "pencil.and.outline") {
                    stickerToEdit = sticker
                }
            }
        }

        if canEdit {
            button.accessibilityAction(named: "Edit Sticker") {
                stickerToEdit = sticker
            }
        } else {
            button
        }
    }

    @MainActor private func loadStickerSet(clearsExisting: Bool = true) async {
        if clearsExisting {
            stickerSet = nil
            isInstalled = nil
        }
        loadErrorMessage = nil
        installationErrorMessage = nil
        do {
            let loadedStickerSet = try await service.getStickerSet(setId: reference.id)
            guard !Task.isCancelled else { return }
            stickerSet = loadedStickerSet
            isInstalled = loadedStickerSet.isInstalled
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            loadErrorMessage = telegramStickerErrorDescription(error)
            await Task.yield()
            loadErrorIsFocused = true
        }
    }

    @MainActor private func changeInstallationState() async {
        guard let action = pendingInstallationAction else { return }
        defer { pendingInstallationAction = nil }
        do {
            _ = try await service.changeStickerSet(
                isArchived: false,
                isInstalled: action.installs,
                setId: reference.id,
            )
            guard !Task.isCancelled else { return }
            isInstalled = action.installs
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            installationErrorMessage = "Sticker pack couldn't be updated: \(telegramStickerErrorDescription(error))"
            await Task.yield()
            installationErrorIsFocused = true
        }
    }
}
