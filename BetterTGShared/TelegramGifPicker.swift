// TelegramGifPicker.swift

import SwiftUI
@preconcurrency import TDLibKit

// MARK: - TelegramAnimationSending

enum TelegramAnimationSending {
    // MARK: Internal

    static func content(
        for animation: TDLibKit.Animation,
        animationFile: InputFile? = nil,
        caption: FormattedText? = nil,
        duration: Int? = nil,
    ) -> InputMessageContent {
        .inputMessageAnimation(.init(
            animation: .init(
                addedStickerFileIds: [],
                animation: animationFile ?? .inputFileId(.init(id: animation.animation.id)),
                duration: duration ?? animation.duration,
                height: animation.height,
                thumbnail: nil,
                width: animation.width,
            ),
            caption: caption,
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
        disableNotification: Bool = false,
        schedulingState: MessageSchedulingState? = nil,
        topicId: MessageTopic? = nil,
    ) async throws -> Message {
        let messages = try await TelegramMessageSending.send(
            service: service,
            chatId: chatId,
            contents: [content(for: animation)],
            replyTo: TelegramMessageSending.replyTo(messageId: replyToMessageId),
            schedulingState: schedulingState,
            disableNotification: disableNotification,
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
        disableNotification: Bool = false,
        schedulingState: MessageSchedulingState? = nil,
        topicId: MessageTopic? = nil,
    ) async throws -> Message {
        let message = try await service.sendInlineQueryResultMessage(
            chatId: chatId,
            hideViaBot: true,
            options: TelegramMessageSending.sendOptions(
                schedulingState: schedulingState,
                disableNotification: disableNotification,
            ),
            queryId: queryId,
            replyTo: TelegramMessageSending.replyTo(messageId: replyToMessageId),
            resultId: resultId,
            topicId: topicId,
        )
        service.mergeMessages(chatId: chatId, messages: [message])
        await remember(message, service: service)
        return message
    }

    @discardableResult static func sendWithCaption(
        _ animation: TDLibKit.Animation,
        caption: String,
        service: any TelegramService,
        chatId: Int64,
        replyToMessageId: Int64?,
        topicId: MessageTopic? = nil,
    ) async throws -> Message {
        let file = try await service.downloadFile(
            fileId: animation.animation.id,
            limit: 0,
            offset: 0,
            priority: 32,
            synchronous: true,
        )
        guard file.local.isDownloadingCompleted, !file.local.path.isEmpty else {
            throw TelegramAnimationSendingError.downloadFailed
        }
        return try await sendLocal(
            animation,
            fileURL: URL(filePath: file.local.path),
            caption: caption,
            duration: animation.duration,
            service: service,
            chatId: chatId,
            replyToMessageId: replyToMessageId,
            topicId: topicId,
        )
    }

    @discardableResult static func sendLocal(
        _ animation: TDLibKit.Animation,
        fileURL: URL,
        caption: String,
        duration: Int,
        service: any TelegramService,
        chatId: Int64,
        replyToMessageId: Int64?,
        topicId: MessageTopic? = nil,
    ) async throws -> Message {
        let formattedCaption = await TelegramTextFormatting.addingAutomaticEntities(
            service: service,
            to: FormattedText(entities: [], text: caption),
        )
        let messages = try await TelegramMessageSending.send(
            service: service,
            chatId: chatId,
            contents: [content(
                for: animation,
                animationFile: .inputFileLocal(.init(path: fileURL.path(percentEncoded: false))),
                caption: formattedCaption,
                duration: duration,
            )],
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
/// one shared search field and tab switcher.
struct TelegramGifPickerContent<Preview: View>: View {
    // MARK: Internal

    let service: any TelegramService
    let chatId: Int64
    let replyToMessageId: Int64?
    let allowsSendWhenOnline: Bool
    let topicId: MessageTopic?
    let query: String
    let onSent: @MainActor () async -> Void
    let preview: (TDLibKit.Animation) -> Preview

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                if normalizedQuery.isEmpty, !emojiCategories.isEmpty {
                    TelegramEmojiCategoryBar(
                        categories: emojiCategories,
                        selectedCategory: selectedEmojiCategory,
                        onSelect: { selectedEmojiCategory = $0 },
                    )
                }

                if normalizedQuery.isEmpty, selectedEmojiCategory == nil {
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
        .task { await loadEmojiCategories() }
        .task(id: searchKey) { await search() }
        .onChange(of: normalizedQuery) { _, newValue in
            if !newValue.isEmpty {
                selectedEmojiCategory = nil
            }
        }
        .refreshable {
            await loadSaved(force: true)
            await loadTrending(force: true)
        }
        .sheet(item: $itemToSchedule) { item in
            TelegramScheduleSendView(allowsSendWhenOnline: allowsSendWhenOnline) { state in
                send(item, schedulingState: state)
            }
        }
        .sheet(item: $itemForCaption) { item in
            TelegramGifCaptionComposer(
                onSend: { caption in
                    try await sendWithCaption(item, caption: caption)
                },
                preview: {
                    preview(item.animation)
                        .aspectRatio(item.aspectRatio, contentMode: .fit)
                },
            )
        }
        .sheet(item: $itemForEditing) { item in
            TelegramGifEditor(
                animation: item.animation,
                service: service,
                chatId: chatId,
                onSend: { url, caption, duration in
                    _ = try await TelegramAnimationSending.sendLocal(
                        item.animation,
                        fileURL: url,
                        caption: caption,
                        duration: duration,
                        service: service,
                        chatId: chatId,
                        replyToMessageId: replyToMessageId,
                        topicId: topicId,
                    )
                    await onSent()
                },
            )
        }
    }

    // MARK: Private

    @AccessibilityFocusState private var feedbackIsFocused: Bool
    @State private var savedAnimations = [TDLibKit.Animation]()
    @State private var trendingResults = [GifPickerSearchResult]()
    @State private var searchResults = [GifPickerSearchResult]()
    @State private var emojiCategories = [EmojiCategory]()
    @State private var selectedEmojiCategory: EmojiCategory?
    @State private var isLoadingSaved = false
    @State private var isLoadingTrending = false
    @State private var isSearching = false
    @State private var hasLoadedSaved = false
    @State private var hasLoadedTrending = false
    @State private var sendingItemId: String?
    @State private var mutatingItemId: String?
    @State private var feedbackMessage: String?
    @State private var animationSearchBotId: Int64?
    @State private var nextSearchOffset = ""
    @State private var isLoadingMoreSearchResults = false
    @State private var nextTrendingOffset = ""
    @State private var isLoadingMoreTrendingResults = false
    @State private var itemToSchedule: GifPickerItem?
    @State private var itemForCaption: GifPickerItem?
    @State private var itemForEditing: GifPickerItem?

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

    private var savedAnimationFileIds: Set<Int> {
        Set(savedAnimations.map(\.animation.id))
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
                    GifPickerItem(id: "saved:\($0.animation.id)", animation: $0, source: .saved, isSaved: true)
                })
            }
            if !trendingResults.isEmpty {
                sectionHeading("Trending")
                gifGrid(trendingResults.map {
                    GifPickerItem(
                        id: "trending:\($0.resultId)",
                        animation: $0.animation,
                        source: .searchResult(queryId: $0.queryId, resultId: $0.resultId),
                        isSaved: savedAnimationFileIds.contains($0.animation.animation.id),
                    )
                })
                if isLoadingMoreTrendingResults {
                    ProgressView("Loading more trending GIFs")
                } else if !nextTrendingOffset.isEmpty {
                    Button("Load More Trending GIFs", systemImage: "arrow.down.circle") {
                        Task { await loadMoreTrendingResults() }
                    }
                    .task(id: nextTrendingOffset) { await loadMoreTrendingResults() }
                }
            }
        }
    }

    @ViewBuilder private var searchContent: some View {
        if isSearching {
            ProgressView("Searching GIFs")
        } else if searchResults.isEmpty, feedbackMessage == nil {
            if let selectedEmojiCategory {
                ContentUnavailableView(
                    "No GIFs",
                    systemImage: "photo.on.rectangle",
                    description: Text("No GIFs were found in \(selectedEmojiCategory.name)."),
                )
                .frame(maxWidth: .infinity)
            } else {
                ContentUnavailableView.search(text: normalizedQuery)
                    .frame(maxWidth: .infinity)
            }
        } else {
            sectionHeading(selectedEmojiCategory?.name ?? "Search Results")
            gifGrid(searchResults.map {
                GifPickerItem(
                    id: "search:\($0.resultId)",
                    animation: $0.animation,
                    source: .searchResult(queryId: $0.queryId, resultId: $0.resultId),
                    isSaved: savedAnimationFileIds.contains($0.animation.animation.id),
                )
            })

            if isLoadingMoreSearchResults {
                ProgressView("Loading more GIFs")
            } else if !nextSearchOffset.isEmpty {
                Button("Load More GIFs", systemImage: "arrow.down.circle") {
                    Task { await loadMoreSearchResults() }
                }
                .task(id: nextSearchOffset) { await loadMoreSearchResults() }
            }
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
                        if sendingItemId == item.id || mutatingItemId == item.id {
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
                .contextMenu {
                    Button("Send Silently", systemImage: "bell.slash") {
                        send(item, disableNotification: true)
                    }

                    if item.isSaved {
                        Button("Schedule Send…", systemImage: "clock") {
                            itemToSchedule = item
                        }
                    }

                    Button("Add Caption…", systemImage: "text.bubble") {
                        itemForCaption = item
                    }

                    Button("Edit GIF…", systemImage: "slider.horizontal.3") {
                        itemForEditing = item
                    }

                    if item.isSaved {
                        Button("Delete from Saved GIFs", systemImage: "trash", role: .destructive) {
                            updateSavedState(for: item)
                        }
                        .disabled(mutatingItemId != nil)
                    } else {
                        Button("Save GIF", systemImage: "bookmark") {
                            updateSavedState(for: item)
                        }
                        .disabled(mutatingItemId != nil)
                    }
                } preview: {
                    TelegramGifLoopingPreview(animation: item.animation, service: service)
                        .aspectRatio(item.aspectRatio, contentMode: .fit)
                        .frame(width: 240, height: 200)
                }
                .accessibilityActions {
                    Button("Add Caption") {
                        itemForCaption = item
                    }
                    Button("Edit GIF") {
                        itemForEditing = item
                    }
                    if item.isSaved {
                        Button("Send Later") {
                            itemToSchedule = item
                        }
                    }
                }
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
            nextTrendingOffset = results.nextOffset
        } catch {
            // Trending is a nice-to-have on top of Saved - fail silently rather than blocking the
            // picker with an error over something that isn't the user's own data.
        }
        hasLoadedTrending = true
        isLoadingTrending = false
    }

    @MainActor private func loadMoreTrendingResults() async {
        guard !isLoadingMoreTrendingResults,
              !nextTrendingOffset.isEmpty,
              let animationSearchBotId
        else { return }
        let requestedOffset = nextTrendingOffset
        isLoadingMoreTrendingResults = true
        defer { isLoadingMoreTrendingResults = false }
        do {
            let results = try await service.getInlineQueryResults(
                botUserId: animationSearchBotId,
                chatId: chatId,
                offset: requestedOffset,
                query: "",
                userLocation: nil,
            )
            guard !Task.isCancelled else { return }
            var existingIds = Set(trendingResults.map(\.resultId))
            trendingResults += Self.animationResults(from: results).filter {
                existingIds.insert($0.resultId).inserted
            }
            nextTrendingOffset = results.nextOffset
        } catch {
            guard !Task.isCancelled else { return }
            showFeedback("More trending GIFs couldn't be loaded: \(telegramErrorDescription(error))")
        }
    }

    @MainActor private func resolveSearchBotIfNeeded() async {
        guard animationSearchBotId == nil else { return }
        guard case .optionValueString(let value) = try? await service.getOption(name: "animation_search_bot_username"),
              !value.value.isEmpty
        else { return }
        guard let chat = try? await service.searchPublicChat(username: value.value) else { return }
        animationSearchBotId = chat.id
    }

    @MainActor private func loadEmojiCategories() async {
        guard emojiCategories.isEmpty else { return }
        guard let categories = try? await service.getEmojiCategories(type: .emojiCategoryTypeDefault) else { return }
        emojiCategories = categories.categories.filter {
            if case .emojiCategorySourceSearch = $0.source {
                true
            } else {
                false
            }
        }
    }

    @MainActor private func search() async {
        guard !activeSearchQuery.isEmpty else {
            searchResults = []
            nextSearchOffset = ""
            isSearching = false
            return
        }
        if animationSearchBotId == nil {
            await resolveSearchBotIfNeeded()
        }
        guard let animationSearchBotId else {
            searchResults = []
            nextSearchOffset = ""
            isSearching = false
            showFeedback("GIF search isn't available right now.")
            return
        }

        isSearching = true
        nextSearchOffset = ""
        feedbackMessage = nil
        feedbackIsFocused = false
        do {
            let results = try await service.getInlineQueryResults(
                botUserId: animationSearchBotId,
                chatId: chatId,
                offset: "",
                query: activeSearchQuery,
                userLocation: nil,
            )
            guard !Task.isCancelled else { return }
            searchResults = Self.animationResults(from: results)
            nextSearchOffset = results.nextOffset
            isSearching = false
        } catch {
            guard !Task.isCancelled else { return }
            searchResults = []
            nextSearchOffset = ""
            isSearching = false
            showFeedback("GIF search failed: \(telegramErrorDescription(error))")
        }
    }

    private func send(
        _ item: GifPickerItem,
        disableNotification: Bool = false,
        schedulingState: MessageSchedulingState? = nil,
    ) {
        guard sendingItemId == nil else { return }
        sendingItemId = item.id
        feedbackMessage = nil
        feedbackIsFocused = false
        Task {
            do {
                if schedulingState != nil, item.isSaved {
                    try await TelegramAnimationSending.send(
                        item.animation,
                        service: service,
                        chatId: chatId,
                        replyToMessageId: replyToMessageId,
                        disableNotification: disableNotification,
                        schedulingState: schedulingState,
                        topicId: topicId,
                    )
                } else {
                    switch item.source {
                    case .saved:
                        try await TelegramAnimationSending.send(
                            item.animation,
                            service: service,
                            chatId: chatId,
                            replyToMessageId: replyToMessageId,
                            disableNotification: disableNotification,
                            schedulingState: schedulingState,
                            topicId: topicId,
                        )
                    case .searchResult(let queryId, let resultId):
                        try await TelegramAnimationSending.sendSearchResult(
                            queryId: queryId,
                            resultId: resultId,
                            service: service,
                            chatId: chatId,
                            replyToMessageId: replyToMessageId,
                            disableNotification: disableNotification,
                            schedulingState: schedulingState,
                            topicId: topicId,
                        )
                    }
                }
                await onSent()
            } catch {
                showFeedback("GIF couldn't be sent: \(telegramErrorDescription(error))")
            }
            sendingItemId = nil
        }
    }

    @MainActor private func sendWithCaption(_ item: GifPickerItem, caption: String) async throws {
        _ = try await TelegramAnimationSending.sendWithCaption(
            item.animation,
            caption: caption,
            service: service,
            chatId: chatId,
            replyToMessageId: replyToMessageId,
            topicId: topicId,
        )
        await onSent()
    }

    @MainActor private func loadMoreSearchResults() async {
        guard !isLoadingMoreSearchResults,
              !nextSearchOffset.isEmpty,
              let animationSearchBotId
        else { return }
        let requestedQuery = activeSearchQuery
        let requestedOffset = nextSearchOffset
        isLoadingMoreSearchResults = true
        defer { isLoadingMoreSearchResults = false }
        do {
            let results = try await service.getInlineQueryResults(
                botUserId: animationSearchBotId,
                chatId: chatId,
                offset: requestedOffset,
                query: requestedQuery,
                userLocation: nil,
            )
            guard !Task.isCancelled, activeSearchQuery == requestedQuery else { return }
            var existingIds = Set(searchResults.map(\.resultId))
            searchResults += Self.animationResults(from: results).filter {
                existingIds.insert($0.resultId).inserted
            }
            nextSearchOffset = results.nextOffset
        } catch {
            guard !Task.isCancelled else { return }
            showFeedback("More GIFs couldn't be loaded: \(telegramErrorDescription(error))")
        }
    }

    private func updateSavedState(for item: GifPickerItem) {
        guard mutatingItemId == nil else { return }
        mutatingItemId = item.id
        Task {
            do {
                let file = InputFile.inputFileId(.init(id: item.animation.animation.id))
                _ =
                    if item.isSaved {
                        try await service.removeSavedAnimation(animation: file)
                    } else {
                        try await service.addSavedAnimation(animation: file)
                    }
                await loadSaved(force: true)
            } catch {
                showFeedback("Saved GIFs couldn't be updated: \(telegramErrorDescription(error))")
            }
            mutatingItemId = nil
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
    let isSaved: Bool

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
    case downloadFailed
    case noMessageReturned

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .downloadFailed:
            "The GIF couldn't be downloaded for editing."
        case .noMessageReturned:
            "Telegram accepted the GIF but didn't return the sent message."
        }
    }
}
