// TelegramStickerSuggestionBar.swift

import SwiftUI
import TDLibKit

struct TelegramStickerSuggestionBar<Preview: View>: View {
    // MARK: Internal

    let service: any TelegramService
    let chatId: Int64
    let replyToMessageId: Int64?
    let topicId: MessageTopic?
    let text: String
    let isEnabled: Bool
    let onSendingChanged: @MainActor (Bool) -> Void
    let onSent: @MainActor () async -> Void
    let preview: (Sticker) -> Preview

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading sticker suggestions")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
            } else if !stickers.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sticker Suggestions")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityAddTraits(.isHeader)
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 8) {
                            ForEach(stickers, id: \.sticker.id) { sticker in
                                suggestionButton(sticker)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .accessibilityFocused($errorIsFocused)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
            }
        }
        .task(id: suggestedEmoji) { await loadSuggestions() }
        .task(id: pendingSticker?.sticker.id) { await sendPendingSticker() }
        .task(id: favoriteMutation?.sticker.id) { await updateFavoriteState() }
        .sheet(item: $selectedPack) { reference in
            TelegramStickerPackPreview(
                reference: reference,
                service: service,
                onSelect: select,
                preview: preview,
            )
        }
    }

    // MARK: Private

    @AccessibilityFocusState private var errorIsFocused: Bool
    @State private var stickers = [Sticker]()
    @State private var favoriteFileIds = Set<Int>()
    @State private var pendingSticker: Sticker?
    @State private var favoriteMutation: Sticker?
    @State private var selectedPack: TelegramStickerPackReference?
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var suggestedEmoji: String? {
        guard isEnabled else { return nil }
        return TelegramStickerSuggestionQuery.emoji(from: text)
    }

    @ViewBuilder private func suggestionButton(_ sticker: Sticker) -> some View {
        let presentation = TelegramStickerPresentation(sticker)
        let isFavorite = favoriteFileIds.contains(sticker.sticker.id)
        let packReference = TelegramStickerPackReference(sticker: sticker)
        let button = Button(action: { select(sticker) }) {
            ZStack {
                preview(sticker)
                    .accessibilityHidden(true)
                if pendingSticker?.sticker.id == sticker.sticker.id
                    || favoriteMutation?.sticker.id == sticker.sticker.id
                {
                    ProgressView()
                        .accessibilityHidden(true)
                }
            }
            .frame(minWidth: 64, minHeight: 64)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(pendingSticker != nil || favoriteMutation != nil)
        .accessibilityLabel(presentation.accessibilityLabel)
        .contextMenu {
            if let packReference {
                Button("View Sticker Pack", systemImage: "square.stack.3d.up") {
                    selectedPack = packReference
                }
            }

            Button(
                isFavorite ? "Remove from Favorites" : "Add to Favorites",
                systemImage: isFavorite ? "star.slash" : "star",
            ) {
                favoriteMutation = sticker
            }
        }
        .accessibilityAction(named: isFavorite ? "Remove from Favorites" : "Add to Favorites") {
            favoriteMutation = sticker
        }

        if let packReference {
            button.accessibilityAction(named: "View Sticker Pack") {
                selectedPack = packReference
            }
        } else {
            button
        }
    }

    @MainActor private func loadSuggestions() async {
        guard let suggestedEmoji else {
            stickers = []
            favoriteFileIds = []
            isLoading = false
            errorMessage = nil
            return
        }
        isLoading = true
        errorMessage = nil
        let currentUser = try? await service.getMe()
        guard !Task.isCancelled, suggestedEmoji == self.suggestedEmoji else { return }
        let favorites = try? await service.getFavoriteStickers()
        guard !Task.isCancelled, suggestedEmoji == self.suggestedEmoji else { return }
        do {
            let result = try await service.getStickers(
                chatId: chatId,
                limit: 20,
                query: suggestedEmoji,
                stickerType: .stickerTypeRegular,
            )
            guard !Task.isCancelled, suggestedEmoji == self.suggestedEmoji else { return }
            let allowsPremium = currentUser?.isPremium == true
            stickers = telegramUniqueStickers(result.stickers).filter {
                allowsPremium || !TelegramStickerPresentation($0).isPremium
            }
            favoriteFileIds = Set(favorites?.stickers.map(\.sticker.id) ?? [])
            isLoading = false
        } catch is CancellationError {
            return
        } catch {
            // Suggestions are additive. A temporary lookup failure must not obstruct the composer.
            stickers = []
            favoriteFileIds = []
            isLoading = false
        }
    }

    @MainActor private func sendPendingSticker() async {
        guard let pendingSticker else { return }
        onSendingChanged(true)
        defer {
            self.pendingSticker = nil
            onSendingChanged(false)
        }
        do {
            try await TelegramStickerSending.send(
                pendingSticker,
                service: service,
                chatId: chatId,
                replyToMessageId: replyToMessageId,
                topicId: topicId,
            )
            await onSent()
        } catch is CancellationError {
            return
        } catch {
            showError("Sticker couldn't be sent: \(telegramErrorDescription(error))")
        }
    }

    @MainActor private func updateFavoriteState() async {
        guard let sticker = favoriteMutation else { return }
        defer { favoriteMutation = nil }
        let file = InputFile.inputFileId(.init(id: sticker.sticker.id))
        let wasFavorite = favoriteFileIds.contains(sticker.sticker.id)
        do {
            if wasFavorite {
                _ = try await service.removeFavoriteSticker(sticker: file)
                favoriteFileIds.remove(sticker.sticker.id)
            } else {
                _ = try await service.addFavoriteSticker(sticker: file)
                favoriteFileIds.insert(sticker.sticker.id)
            }
        } catch is CancellationError {
            return
        } catch {
            showError("Favorites couldn't be updated: \(telegramErrorDescription(error))")
        }
    }

    private func select(_ sticker: Sticker) {
        guard pendingSticker == nil, favoriteMutation == nil else { return }
        pendingSticker = sticker
        errorMessage = nil
    }

    private func showError(_ message: String) {
        errorMessage = message
        errorIsFocused = true
    }
}
