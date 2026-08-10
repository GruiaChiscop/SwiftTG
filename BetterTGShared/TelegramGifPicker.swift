// TelegramGifPicker.swift

import SwiftUI
@preconcurrency import TDLibKit

// MARK: - TelegramAnimationSending

enum TelegramAnimationSending {
    // MARK: Internal

    static func content(for animation: TDLibKit.Animation) -> InputMessageContent {
        .inputMessageAnimation(.init(
            animation: .init(
                addedStickerFileIds: [],
                animation: .inputFileId(.init(id: animation.animation.id)),
                duration: animation.duration,
                height: animation.height,
                thumbnail: nil,
                width: animation.width,
            ),
            caption: nil,
            hasSpoiler: false,
            showCaptionAboveMedia: false,
        ))
    }

    /// Sends an already-owned (saved) animation directly - a catalog search/trending result
    /// instead goes through `sendSearchResult`, since TDLib requires that path to use the inline
    /// query's own id rather than building `InputMessageContent` by hand.
    @discardableResult static func send(
        _ animation: TDLibKit.Animation,
        service: any TelegramService,
        chatId: Int64,
        replyToMessageId: Int64?,
        topicId: MessageTopic? = nil,
    ) async throws -> Message {
        let messages = try await TelegramMessageSending.send(
            service: service,
            chatId: chatId,
            contents: [content(for: animation)],
            replyTo: TelegramMessageSending.replyTo(messageId: replyToMessageId),
            topicId: topicId,
            onAccepted: { messages in
                service.mergeMessages(chatId: chatId, messages: messages)
            },
        )
        guard let message = messages.first else {
            throw TelegramAnimationSendingError.noMessageReturned
        }
        await remember(message, service: service)
        return message
    }

    /// Sends a GIF picked from catalog search or trending results - real Telegram apps back both
    /// with an inline bot query (see `TelegramGifPickerContent`), so the result must be sent
    /// through `sendInlineQueryResultMessage` using the query's own id, not re-packaged as a fresh
    /// `InputMessageContent`.
    @discardableResult static func sendSearchResult(
        queryId: TdInt64,
        resultId: String,
        service: any TelegramService,
        chatId: Int64,
        replyToMessageId: Int64?,
        topicId: MessageTopic? = nil,
    ) async throws -> Message {
        let message = try await service.sendInlineQueryResultMessage(
            chatId: chatId,
            hideViaBot: true,
            options: nil,
            queryId: queryId,
            replyTo: TelegramMessageSending.replyTo(messageId: replyToMessageId),
            resultId: resultId,
            topicId: topicId,
        )
        service.mergeMessages(chatId: chatId, messages: [message])
        await remember(message, service: service)
        return message
    }

    // MARK: Private

    /// Real Telegram apps add every sent GIF to Saved GIFs automatically, not just ones explicitly
    /// picked from the saved list - `addSavedAnimation` requires an animation TDLib already knows
    /// about server-side, which is only true once sending has actually succeeded.
    private static func remember(_ message: Message, service: any TelegramService) async {
        guard case .messageAnimation(let content) = message.content else { return }
        _ = try? await service.addSavedAnimation(
            animation: .inputFileId(.init(id: content.animation.animation.id)),
        )
    }
}

// MARK: - TelegramGifPickerContent

/// Embedded by `TelegramStickersAndGifsPickerView` alongside `TelegramStickerPickerContent` under
/// one shared `NavigationStack`/search field/tab switcher.
struct TelegramGifPickerContent<Preview: View>: View {
    // MARK: Internal

    let service: any TelegramService
    let chatId: Int64
    let replyToMessageId: Int64?
    let topicId: MessageTopic?
    let query: String
    let onSent: @MainActor () async -> Void
    let preview: (TDLibKit.Animation) -> Preview

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                if normalizedQuery.isEmpty {
                    savedContent
                } else {
                    searchContent
                }

                if let feedbackMessage {
                    Text(feedbackMessage)
                        .foregroundStyle(.red)
                        .accessibilityFocused($feedbackIsFocused)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .task { await loadSavedIfNeeded() }
        .task { await loadTrendingIfNeeded() }
        .task(id: normalizedQuery) { await search() }
        .refreshable {
            await loadSaved(force: true)
            await loadTrending(force: true)
        }
    }

    // MARK: Private

    @AccessibilityFocusState private var feedbackIsFocused: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var savedAnimations = [TDLibKit.Animation]()
    @State private var trendingResults = [GifPickerSearchResult]()
    @State private var searchResults = [GifPickerSearchResult]()
    @State private var isLoadingSaved = false
    @State private var isLoadingTrending = false
    @State private var isSearching = false
    @State private var hasLoadedSaved = false
    @State private var hasLoadedTrending = false
    @State private var sendingItemId: String?
    @State private var feedbackMessage: String?
    @State private var animationSearchBotId: Int64?

    private var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @ViewBuilder private var savedContent: some View {
        if isLoadingSaved, !hasLoadedSaved {
            ProgressView("Loading GIFs")
        } else if savedAnimations.isEmpty, trendingResults.isEmpty, feedbackMessage == nil {
            ContentUnavailableView(
                "No GIFs",
                systemImage: "photo.on.rectangle",
                description: Text("Search for a GIF to send one."),
            )
            .frame(maxWidth: .infinity)
        } else {
            if !savedAnimations.isEmpty {
                sectionHeading("Saved")
                gifGrid(savedAnimations.map {
                    GifPickerItem(id: "saved:\($0.animation.id)", animation: $0, source: .saved)
                })
            }
            if !trendingResults.isEmpty {
                sectionHeading("Trending")
                gifGrid(trendingResults.map {
                    GifPickerItem(
                        id: "trending:\($0.resultId)",
                        animation: $0.animation,
                        source: .searchResult(queryId: $0.queryId, resultId: $0.resultId),
                    )
                })
            }
        }
    }

    @ViewBuilder private var searchContent: some View {
        if isSearching {
            ProgressView("Searching GIFs")
        } else if searchResults.isEmpty, feedbackMessage == nil {
            ContentUnavailableView.search(text: normalizedQuery)
                .frame(maxWidth: .infinity)
        } else {
            sectionHeading("Search Results")
            gifGrid(searchResults.map {
                GifPickerItem(
                    id: "search:\($0.resultId)",
                    animation: $0.animation,
                    source: .searchResult(queryId: $0.queryId, resultId: $0.resultId),
                )
            })
        }
    }

    private func sectionHeading(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .accessibilityAddTraits(.isHeader)
    }

    private func gifGrid(_ items: [GifPickerItem]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120, maximum: 160), spacing: 8)], spacing: 8) {
            ForEach(items) { item in
                Button {
                    send(item)
                } label: {
                    ZStack {
                        preview(item.animation)
                            .accessibilityHidden(true)
                        if sendingItemId == item.id {
                            ProgressView()
                                .accessibilityHidden(true)
                        }
                    }
                    .aspectRatio(item.aspectRatio, contentMode: .fit)
                    .clipShape(.rect(cornerRadius: 10))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(sendingItemId != nil)
                .accessibilityLabel("GIF")
            }
        }
        .padding(.vertical, 4)
    }

    private static func animationResults(from results: InlineQueryResults) -> [GifPickerSearchResult] {
        results.results.compactMap { result in
            guard case .inlineQueryResultAnimation(let animationResult) = result else { return nil }
            return GifPickerSearchResult(
                resultId: animationResult.id,
                queryId: results.inlineQueryId,
                animation: animationResult.animation,
            )
        }
    }

    @MainActor private func loadSavedIfNeeded() async {
        guard !hasLoadedSaved else { return }
        await loadSaved(force: false)
    }

    @MainActor private func loadSaved(force: Bool) async {
        guard force || !hasLoadedSaved else { return }
        guard !isLoadingSaved else { return }
        isLoadingSaved = true
        feedbackMessage = nil
        feedbackIsFocused = false
        do {
            savedAnimations = try await service.getSavedAnimations().animations
        } catch {
            showFeedback("Saved GIFs couldn't be loaded: \(telegramErrorDescription(error))")
        }
        hasLoadedSaved = true
        isLoadingSaved = false
    }

    @MainActor private func loadTrendingIfNeeded() async {
        guard !hasLoadedTrending else { return }
        await loadTrending(force: false)
    }

    /// Mirrors real Telegram clients (Telegram-iOS's `GifContext.trending` case): trending GIFs
    /// are just the same inline-bot search called with an empty query, not a separate API.
    @MainActor private func loadTrending(force: Bool) async {
        guard force || !hasLoadedTrending else { return }
        guard !isLoadingTrending else { return }
        isLoadingTrending = true
        if animationSearchBotId == nil {
            await resolveSearchBotIfNeeded()
        }
        guard let animationSearchBotId else {
            hasLoadedTrending = true
            isLoadingTrending = false
            return
        }
        do {
            let results = try await service.getInlineQueryResults(
                botUserId: animationSearchBotId,
                chatId: chatId,
                offset: "",
                query: "",
                userLocation: nil,
            )
            trendingResults = Self.animationResults(from: results)
        } catch {
            // Trending is a nice-to-have on top of Saved - fail silently rather than blocking the
            // picker with an error over something that isn't the user's own data.
        }
        hasLoadedTrending = true
        isLoadingTrending = false
    }

    @MainActor private func resolveSearchBotIfNeeded() async {
        guard animationSearchBotId == nil else { return }
        guard case .optionValueString(let value) = try? await service.getOption(name: "animation_search_bot_username"),
              !value.value.isEmpty
        else { return }
        guard let chat = try? await service.searchPublicChat(username: value.value) else { return }
        animationSearchBotId = chat.id
    }

    @MainActor private func search() async {
        guard !normalizedQuery.isEmpty else {
            searchResults = []
            isSearching = false
            return
        }
        if animationSearchBotId == nil {
            await resolveSearchBotIfNeeded()
        }
        guard let animationSearchBotId else {
            searchResults = []
            isSearching = false
            showFeedback("GIF search isn't available right now.")
            return
        }

        isSearching = true
        feedbackMessage = nil
        feedbackIsFocused = false
        do {
            let results = try await service.getInlineQueryResults(
                botUserId: animationSearchBotId,
                chatId: chatId,
                offset: "",
                query: normalizedQuery,
                userLocation: nil,
            )
            guard !Task.isCancelled else { return }
            searchResults = Self.animationResults(from: results)
            isSearching = false
        } catch {
            guard !Task.isCancelled else { return }
            searchResults = []
            isSearching = false
            showFeedback("GIF search failed: \(telegramErrorDescription(error))")
        }
    }

    private func send(_ item: GifPickerItem) {
        guard sendingItemId == nil else { return }
        sendingItemId = item.id
        feedbackMessage = nil
        feedbackIsFocused = false
        Task {
            do {
                switch item.source {
                case .saved:
                    try await TelegramAnimationSending.send(
                        item.animation,
                        service: service,
                        chatId: chatId,
                        replyToMessageId: replyToMessageId,
                        topicId: topicId,
                    )
                case .searchResult(let queryId, let resultId):
                    try await TelegramAnimationSending.sendSearchResult(
                        queryId: queryId,
                        resultId: resultId,
                        service: service,
                        chatId: chatId,
                        replyToMessageId: replyToMessageId,
                        topicId: topicId,
                    )
                }
                await onSent()
                dismiss()
            } catch {
                showFeedback("GIF couldn't be sent: \(telegramErrorDescription(error))")
            }
            sendingItemId = nil
        }
    }

    @MainActor private func showFeedback(_ message: String) {
        feedbackMessage = message
        Task { @MainActor in
            await Task.yield()
            feedbackIsFocused = true
        }
    }
}

// MARK: - GifPickerItem

private struct GifPickerItem: Identifiable {
    enum Source {
        case saved
        case searchResult(queryId: TdInt64, resultId: String)
    }

    let id: String
    let animation: TDLibKit.Animation
    let source: Source

    var aspectRatio: CGFloat {
        CGFloat(max(animation.width, 1)) / CGFloat(max(animation.height, 1))
    }
}

// MARK: - GifPickerSearchResult

private struct GifPickerSearchResult {
    let resultId: String
    let queryId: TdInt64
    let animation: TDLibKit.Animation
}

// MARK: - TelegramAnimationSendingError

private enum TelegramAnimationSendingError: LocalizedError {
    case noMessageReturned

    // MARK: Internal

    var errorDescription: String? {
        "Telegram accepted the GIF but didn't return the sent message."
    }
}
