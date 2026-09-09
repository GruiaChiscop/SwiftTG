// TelegramEditorStickerLibrary.swift

import SwiftUI
import TDLibKit

struct TelegramEditorStickerLibrary: View {
    // MARK: Internal

    let service: any TelegramService
    let chatId: Int64
    let query: String
    let onSelected: (TelegramStickerOverlay) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if selectedStickerSetInfo == nil, normalizedQuery.isEmpty, !emojiCategories.isEmpty {
                TelegramEmojiCategoryBar(
                    categories: emojiCategories,
                    selectedCategory: selectedEmojiCategory,
                    onSelect: selectCategory,
                )
                .padding(.horizontal)
            }

            if let selectedStickerSetInfo {
                HStack {
                    Button("Sticker Packs", systemImage: "chevron.left", action: closeStickerSet)
                    Spacer()
                    Text(selectedStickerSetInfo.title)
                        .bold()
                        .accessibilityAddTraits(.isHeader)
                }
                .padding()
                Divider()
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    content
                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .accessibilityFocused($errorIsFocused)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
        }
        .task { await loadLibraryIfNeeded() }
        .task(id: searchKey) { await search() }
        .task(id: selectedStickerSetInfo?.id) { await loadSelectedStickerSet() }
        .onChange(of: normalizedQuery) { _, newValue in
            if !newValue.isEmpty {
                selectedEmojiCategory = nil
                closeStickerSet()
            }
        }
    }

    // MARK: Private

    @AccessibilityFocusState private var errorIsFocused: Bool
    @State private var favoriteStickers = [Sticker]()
    @State private var recentStickers = [Sticker]()
    @State private var stickerSets = [StickerSetInfo]()
    @State private var emojiCategories = [EmojiCategory]()
    @State private var selectedEmojiCategory: EmojiCategory?
    @State private var selectedStickerSetInfo: StickerSetInfo?
    @State private var selectedStickerSet: StickerSet?
    @State private var searchResults = [Sticker]()
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var isSearching = false
    @State private var selectingFileId: Int?
    @State private var errorMessage: String?

    private var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var searchKey: String {
        "\(normalizedQuery)|\(selectedEmojiCategory?.name ?? "")"
    }

    private var packTitles: [TdInt64: String] {
        Dictionary(uniqueKeysWithValues: stickerSets.map { ($0.id, $0.title) })
    }

    @ViewBuilder private var content: some View {
        if let selectedStickerSetInfo {
            if let selectedStickerSet {
                TelegramEditorStickerGrid(
                    stickers: selectedStickerSet.stickers,
                    packTitles: [selectedStickerSetInfo.id: selectedStickerSetInfo.title],
                    service: service,
                    selectingFileId: selectingFileId,
                    onSelect: selectSticker,
                )
            } else if errorMessage == nil {
                ProgressView("Loading \(selectedStickerSetInfo.title)")
                    .frame(maxWidth: .infinity)
            }
        } else if !normalizedQuery.isEmpty || selectedEmojiCategory != nil {
            if isSearching {
                ProgressView("Searching stickers")
                    .frame(maxWidth: .infinity)
            } else if searchResults.isEmpty, errorMessage == nil {
                ContentUnavailableView.search(text: normalizedQuery)
                    .frame(maxWidth: .infinity)
            } else {
                Text(selectedEmojiCategory?.name ?? "Search Results")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                TelegramEditorStickerGrid(
                    stickers: searchResults,
                    packTitles: packTitles,
                    service: service,
                    selectingFileId: selectingFileId,
                    onSelect: selectSticker,
                )
            }
        } else if isLoading {
            ProgressView("Loading stickers")
                .frame(maxWidth: .infinity)
        } else if favoriteStickers.isEmpty, recentStickers.isEmpty, stickerSets.isEmpty, errorMessage == nil {
            ContentUnavailableView(
                "No Stickers",
                systemImage: "face.smiling",
                description: Text("Install a sticker pack, or search for a sticker."),
            )
            .frame(maxWidth: .infinity)
        } else {
            if !favoriteStickers.isEmpty {
                Text("Favorites")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                TelegramEditorStickerGrid(
                    stickers: favoriteStickers,
                    packTitles: packTitles,
                    service: service,
                    selectingFileId: selectingFileId,
                    onSelect: selectSticker,
                )
            }
            if !recentStickers.isEmpty {
                Text("Recent")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                TelegramEditorStickerGrid(
                    stickers: recentStickers,
                    packTitles: packTitles,
                    service: service,
                    selectingFileId: selectingFileId,
                    onSelect: selectSticker,
                )
            }
            if !stickerSets.isEmpty {
                Text("Sticker Packs")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                ForEach(stickerSets) { stickerSet in
                    TelegramStickerSetPickerRow(
                        stickerSet: stickerSet,
                        isInstalling: false,
                        showsInstallButton: false,
                        onOpen: { openStickerSet(stickerSet) },
                        onInstall: {},
                    )
                }
            }
        }
    }

    @MainActor private func loadLibraryIfNeeded() async {
        guard !hasLoaded, !isLoading else { return }
        isLoading = true
        errorMessage = nil
        var errors = [String]()

        do {
            favoriteStickers = try await telegramUniqueStickers(service.getFavoriteStickers().stickers)
        } catch is CancellationError {
            isLoading = false
            return
        } catch {
            errors.append("Favorite stickers couldn't be loaded: \(telegramStickerErrorDescription(error))")
        }

        do {
            recentStickers = try await telegramRecentStickers(
                service.getRecentStickers(isAttached: false).stickers,
                excluding: favoriteStickers,
            )
        } catch is CancellationError {
            isLoading = false
            return
        } catch {
            errors.append("Recent stickers couldn't be loaded: \(telegramStickerErrorDescription(error))")
        }

        do {
            stickerSets = try await service.getInstalledStickerSets(stickerType: .stickerTypeRegular)
                .sets
                .filter(\.isInstalled)
        } catch is CancellationError {
            isLoading = false
            return
        } catch {
            errors.append("Sticker packs couldn't be loaded: \(telegramStickerErrorDescription(error))")
        }

        if let categories = try? await service.getEmojiCategories(type: .emojiCategoryTypeRegularStickers) {
            emojiCategories = categories.categories
        }
        guard !Task.isCancelled else {
            isLoading = false
            return
        }
        hasLoaded = true
        isLoading = false
        if !errors.isEmpty {
            showError(errors.joined(separator: " "))
        }
    }

    @MainActor private func search() async {
        guard !normalizedQuery.isEmpty || selectedEmojiCategory != nil else {
            searchResults = []
            isSearching = false
            return
        }
        isSearching = true
        errorMessage = nil
        do {
            try await Task.sleep(for: .milliseconds(250))
        } catch {
            isSearching = false
            return
        }

        if let selectedEmojiCategory, case .emojiCategorySourcePremium = selectedEmojiCategory.source {
            do {
                searchResults = try await telegramUniqueStickers(service.getPremiumStickers(limit: 100).stickers)
            } catch is CancellationError {
                isSearching = false
                return
            } catch {
                showError("Premium stickers couldn't be loaded: \(telegramStickerErrorDescription(error))")
            }
            isSearching = false
            return
        }

        let categoryEmojis: [String] =
            if let selectedEmojiCategory,
            case .emojiCategorySourceSearch(let source) = selectedEmojiCategory.source {
                source.emojis
            } else {
                []
            }
        let installedQuery = normalizedQuery.isEmpty ? categoryEmojis.joined(separator: " ") : normalizedQuery
        async let installed = try? service.getStickers(
            chatId: chatId,
            limit: 100,
            query: installedQuery,
            stickerType: .stickerTypeRegular,
        )
        async let catalog = catalogSearch(categoryEmojis: categoryEmojis)
        let (installedResult, catalogResult) = await (installed, catalog)
        guard !Task.isCancelled else { return }
        searchResults = telegramUniqueStickers((installedResult?.stickers ?? []) + (catalogResult ?? []))
        isSearching = false
        if installedResult == nil, catalogResult == nil {
            showError("Sticker search failed.")
        }
    }

    private func catalogSearch(categoryEmojis: [String]) async -> [Sticker]? {
        let resolvedEmojis =
            if categoryEmojis.isEmpty {
                await (try? service.searchEmojis(inputLanguageCodes: nil, text: normalizedQuery))?
                    .emojiKeywords
                    .map(\.emoji)
                    .joined(separator: " ") ?? ""
            } else {
                categoryEmojis.joined(separator: " ")
            }
        return try? await service.searchStickers(
            emojis: resolvedEmojis,
            inputLanguageCodes: nil,
            limit: 50,
            offset: 0,
            query: normalizedQuery,
            stickerType: .stickerTypeRegular,
        )
        .stickers
    }

    @MainActor private func loadSelectedStickerSet() async {
        guard let selectedStickerSetInfo else {
            selectedStickerSet = nil
            return
        }
        selectedStickerSet = nil
        errorMessage = nil
        do {
            let stickerSet = try await service.getStickerSet(setId: selectedStickerSetInfo.id)
            guard !Task.isCancelled else { return }
            selectedStickerSet = stickerSet
        } catch is CancellationError {
            return
        } catch {
            showError("\(selectedStickerSetInfo.title) couldn't be loaded: \(telegramStickerErrorDescription(error))")
        }
    }

    private func selectCategory(_ category: EmojiCategory?) {
        selectedEmojiCategory = category
    }

    private func openStickerSet(_ stickerSet: StickerSetInfo) {
        selectedStickerSetInfo = stickerSet
    }

    private func closeStickerSet() {
        selectedStickerSetInfo = nil
        selectedStickerSet = nil
    }

    private func selectSticker(_ sticker: Sticker) {
        guard selectingFileId == nil else { return }
        selectingFileId = sticker.sticker.id
        errorMessage = nil
        Task {
            do {
                let overlay = try await TelegramEditorOverlaySelection.download(sticker: sticker, service: service)
                onSelected(overlay)
            } catch is CancellationError {
                selectingFileId = nil
            } catch {
                selectingFileId = nil
                showError("Sticker couldn't be added: \(telegramStickerErrorDescription(error))")
            }
        }
    }

    @MainActor private func showError(_ message: String) {
        errorMessage = message
        // Let the error `Text` mount before moving VoiceOver focus to it.
        Task { @MainActor in
            await Task.yield()
            errorIsFocused = true
        }
    }
}
