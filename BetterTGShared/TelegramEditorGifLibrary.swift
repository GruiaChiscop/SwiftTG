// TelegramEditorGifLibrary.swift

import SwiftUI
@preconcurrency import TDLibKit

struct TelegramEditorGifLibrary: View {
    // MARK: Internal

    let service: any TelegramService
    let chatId: Int64
    let query: String
    let onSelected: (TelegramStickerOverlay) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                if normalizedQuery.isEmpty, !emojiCategories.isEmpty {
                    TelegramEmojiCategoryBar(
                        categories: emojiCategories,
                        selectedCategory: selectedEmojiCategory,
                        onSelect: selectCategory,
                    )
                }

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
        .task { await loadLibraryIfNeeded() }
        .task(id: searchKey) { await search() }
        .onChange(of: normalizedQuery) { _, newValue in
            if !newValue.isEmpty {
                selectedEmojiCategory = nil
            }
        }
    }

    // MARK: Private

    @AccessibilityFocusState private var errorIsFocused: Bool
    @State private var savedAnimations = [TDLibKit.Animation]()
    @State private var trendingAnimations = [TDLibKit.Animation]()
    @State private var searchResults = [TDLibKit.Animation]()
    @State private var emojiCategories = [EmojiCategory]()
    @State private var selectedEmojiCategory: EmojiCategory?
    @State private var animationSearchBotId: Int64?
    @State private var nextTrendingOffset = ""
    @State private var nextSearchOffset = ""
    @State private var isLoading = false
    @State private var isSearching = false
    @State private var isLoadingMore = false
    @State private var selectingFileId: Int?
    @State private var errorMessage: String?

    private var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var activeSearchQuery: String {
        if !normalizedQuery.isEmpty {
            normalizedQuery
        } else if let selectedEmojiCategory,
                  case .emojiCategorySourceSearch(let source) = selectedEmojiCategory.source
        {
            source.emojis.joined(separator: " ")
        } else {
            ""
        }
    }

    private var searchKey: String {
        "\(normalizedQuery)|\(selectedEmojiCategory?.name ?? "")"
    }

    @ViewBuilder private var content: some View {
        if !activeSearchQuery.isEmpty {
            if isSearching {
                ProgressView("Searching GIFs")
                    .frame(maxWidth: .infinity)
            } else if searchResults.isEmpty, errorMessage == nil {
                ContentUnavailableView.search(text: normalizedQuery)
                    .frame(maxWidth: .infinity)
            } else {
                Text(selectedEmojiCategory?.name ?? "Search Results")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                TelegramEditorGifGrid(
                    animations: searchResults,
                    service: service,
                    selectingFileId: selectingFileId,
                    onSelect: selectAnimation,
                )
                if isLoadingMore {
                    ProgressView("Loading more GIFs")
                } else if !nextSearchOffset.isEmpty {
                    Button("Load More GIFs", systemImage: "arrow.down.circle", action: loadMoreSearchResults)
                }
            }
        } else if isLoading {
            ProgressView("Loading GIFs")
                .frame(maxWidth: .infinity)
        } else if savedAnimations.isEmpty, trendingAnimations.isEmpty, errorMessage == nil {
            ContentUnavailableView(
                "No GIFs",
                systemImage: "photo.on.rectangle",
                description: Text("Save a GIF, or search for one."),
            )
            .frame(maxWidth: .infinity)
        } else {
            if !savedAnimations.isEmpty {
                Text("Saved")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                TelegramEditorGifGrid(
                    animations: savedAnimations,
                    service: service,
                    selectingFileId: selectingFileId,
                    onSelect: selectAnimation,
                )
            }
            if !trendingAnimations.isEmpty {
                Text("Trending")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                TelegramEditorGifGrid(
                    animations: trendingAnimations,
                    service: service,
                    selectingFileId: selectingFileId,
                    onSelect: selectAnimation,
                )
                if isLoadingMore {
                    ProgressView("Loading more trending GIFs")
                } else if !nextTrendingOffset.isEmpty {
                    Button("Load More Trending GIFs", systemImage: "arrow.down.circle", action: loadMoreTrending)
                }
            }
        }
    }

    @MainActor private func loadLibraryIfNeeded() async {
        guard !isLoading, savedAnimations.isEmpty, trendingAnimations.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        do {
            savedAnimations = try await telegramUniqueAnimations(service.getSavedAnimations().animations)
        } catch is CancellationError {
            isLoading = false
            return
        } catch {
            showError("Saved GIFs couldn't be loaded: \(telegramErrorDescription(error))")
        }

        await resolveSearchBotIfNeeded()
        if let animationSearchBotId {
            do {
                let results = try await service.getInlineQueryResults(
                    botUserId: animationSearchBotId,
                    chatId: chatId,
                    offset: "",
                    query: "",
                    userLocation: nil,
                )
                guard !Task.isCancelled else {
                    isLoading = false
                    return
                }
                trendingAnimations = telegramUniqueAnimations(telegramAnimations(from: results))
                nextTrendingOffset = results.nextOffset
            } catch is CancellationError {
                isLoading = false
                return
            } catch {
                // Saved GIFs remain useful even when the optional trending feed is unavailable.
            }
        }
        if let categories = try? await service.getEmojiCategories(type: .emojiCategoryTypeDefault) {
            emojiCategories = categories.categories.filter {
                if case .emojiCategorySourceSearch = $0.source {
                    true
                } else {
                    false
                }
            }
        }
        isLoading = false
    }

    @MainActor private func search() async {
        guard !activeSearchQuery.isEmpty else {
            searchResults = []
            nextSearchOffset = ""
            isSearching = false
            return
        }
        isSearching = true
        errorMessage = nil
        do {
            try await Task.sleep(for: .milliseconds(250))
        } catch is CancellationError {
            return
        } catch {
            return
        }
        await resolveSearchBotIfNeeded()
        guard let animationSearchBotId else {
            isSearching = false
            showError("GIF search isn't available right now.")
            return
        }
        do {
            let results = try await service.getInlineQueryResults(
                botUserId: animationSearchBotId,
                chatId: chatId,
                offset: "",
                query: activeSearchQuery,
                userLocation: nil,
            )
            guard !Task.isCancelled else { return }
            searchResults = telegramUniqueAnimations(telegramAnimations(from: results))
            nextSearchOffset = results.nextOffset
            isSearching = false
        } catch is CancellationError {
            return
        } catch {
            searchResults = []
            nextSearchOffset = ""
            isSearching = false
            showError("GIF search failed: \(telegramErrorDescription(error))")
        }
    }

    @MainActor private func loadMore(offset: String, query: String, appendingToSearch: Bool) async {
        guard !isLoadingMore, !offset.isEmpty, let animationSearchBotId else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let results = try await service.getInlineQueryResults(
                botUserId: animationSearchBotId,
                chatId: chatId,
                offset: offset,
                query: query,
                userLocation: nil,
            )
            guard !Task.isCancelled else { return }
            if appendingToSearch {
                searchResults = telegramUniqueAnimations(searchResults + telegramAnimations(from: results))
                nextSearchOffset = results.nextOffset
            } else {
                trendingAnimations = telegramUniqueAnimations(trendingAnimations + telegramAnimations(from: results))
                nextTrendingOffset = results.nextOffset
            }
        } catch is CancellationError {
            return
        } catch {
            showError("More GIFs couldn't be loaded: \(telegramErrorDescription(error))")
        }
    }

    @MainActor private func resolveSearchBotIfNeeded() async {
        guard animationSearchBotId == nil else { return }
        guard case .optionValueString(let value) = try? await service.getOption(
            name: "animation_search_bot_username",
        ), !value.value.isEmpty,
        let chat = try? await service.searchPublicChat(username: value.value)
        else { return }
        animationSearchBotId = chat.id
    }

    private func loadMoreSearchResults() {
        let offset = nextSearchOffset
        let query = activeSearchQuery
        Task { await loadMore(offset: offset, query: query, appendingToSearch: true) }
    }

    private func loadMoreTrending() {
        let offset = nextTrendingOffset
        Task { await loadMore(offset: offset, query: "", appendingToSearch: false) }
    }

    private func selectCategory(_ category: EmojiCategory?) {
        selectedEmojiCategory = category
    }

    private func selectAnimation(_ animation: TDLibKit.Animation) {
        guard selectingFileId == nil else { return }
        selectingFileId = animation.animation.id
        errorMessage = nil
        Task {
            do {
                let overlay = try await TelegramEditorOverlaySelection.download(
                    animation: animation,
                    service: service,
                )
                onSelected(overlay)
            } catch is CancellationError {
                selectingFileId = nil
            } catch {
                selectingFileId = nil
                showError("GIF couldn't be added: \(telegramErrorDescription(error))")
            }
        }
    }

    private func showError(_ message: String) {
        errorMessage = message
        errorIsFocused = true
    }
}
