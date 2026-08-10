// TelegramStickerPicker.swift

import SwiftUI
import TDLibKit

// MARK: - TelegramStickerSending

enum TelegramStickerSending {
    static func content(for sticker: Sticker) -> InputMessageContent {
        .inputMessageSticker(.init(
            emoji: sticker.emoji,
            sticker: .init(
                height: sticker.height,
                sticker: .inputFileId(.init(id: sticker.sticker.id)),
                thumbnail: nil,
                width: sticker.width,
            ),
        ))
    }

    @discardableResult static func send(
        _ sticker: Sticker,
        service: any TelegramService,
        chatId: Int64,
        replyToMessageId: Int64?,
        disableNotification: Bool = false,
        topicId: MessageTopic? = nil,
    ) async throws -> Message {
        let messages = try await TelegramMessageSending.send(
            service: service,
            chatId: chatId,
            contents: [content(for: sticker)],
            replyTo: TelegramMessageSending.replyTo(messageId: replyToMessageId),
            disableNotification: disableNotification,
            topicId: topicId,
            onAccepted: { messages in
                service.mergeMessages(chatId: chatId, messages: messages)
            },
        )
        guard let message = messages.first else {
            throw TelegramStickerSendingError.noMessageReturned
        }
        return message
    }
}

// MARK: - TelegramStickerPickerContent

/// Embedded by `TelegramStickersAndGifsPickerView` alongside `TelegramGifPickerContent` under one
/// shared search field and tab switcher.
struct TelegramStickerPickerContent<Preview: View>: View {
    // MARK: Internal

    let service: any TelegramService
    let chatId: Int64
    let replyToMessageId: Int64?
    let topicId: MessageTopic?
    let query: String
    let onSent: @MainActor () async -> Void
    let preview: (Sticker) -> Preview

    var body: some View {
        Group {
            if let selectedStickerSet {
                TelegramStickerSetPickerView(
                    stickerSetInfo: selectedStickerSet,
                    service: service,
                    sendingStickerFileId: sendingStickerFileId,
                    favoriteStickerFileIds: favoriteStickerFileIds,
                    onBack: { self.selectedStickerSet = nil },
                    onSelect: { send($0) },
                    onSelectSilently: { send($0, disableNotification: true) },
                    onToggleFavorite: toggleFavorite,
                    preview: preview,
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        if normalizedQuery.isEmpty {
                            Button("Create Sticker", systemImage: "plus") {
                                showsCreationComposer = true
                            }
                            .buttonStyle(.bordered)

                            libraryContent
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
            }
        }
        .task { await loadLibraryIfNeeded() }
        .task(id: normalizedQuery) { await search() }
        .refreshable { await loadLibrary(force: true) }
        .alert("Telegram Premium Required", isPresented: $showsPremiumRequiredAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Telegram Premium is required to send this sticker.")
        }
        .sheet(isPresented: $showsCreationComposer) {
            TelegramStickerCreationComposerView(service: service) { _ in
                await loadLibrary(force: true)
            }
        }
    }

    // MARK: Private

    @AccessibilityFocusState private var feedbackIsFocused: Bool
    @State private var favoriteStickers = [Sticker]()
    @State private var recentStickers = [Sticker]()
    @State private var stickerSets = [StickerSetInfo]()
    @State private var trendingStickerSets = [StickerSetInfo]()
    @State private var searchResults = [Sticker]()
    @State private var isLoadingLibrary = false
    @State private var isSearching = false
    @State private var hasLoadedLibrary = false
    @State private var sendingStickerFileId: Int?
    @State private var feedbackMessage: String?
    @State private var hasPremium: Bool?
    @State private var showsPremiumRequiredAlert = false
    @State private var showsClearRecentConfirmation = false
    @State private var showsCreationComposer = false
    @State private var selectedStickerSet: StickerSetInfo?
    @State private var installingStickerSetId: TdInt64?
    @State private var mutatingStickerFileId: Int?

    private var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var setTitles: [TdInt64: String] {
        var titles = [TdInt64: String]()
        for stickerSet in stickerSets + trendingStickerSets {
            titles[stickerSet.id] = stickerSet.title
        }
        return titles
    }

    private var favoriteStickerFileIds: Set<Int> {
        Set(favoriteStickers.map(\.sticker.id))
    }

    @ViewBuilder private var libraryContent: some View {
        if isLoadingLibrary, !hasLoadedLibrary {
            ProgressView("Loading stickers")
        } else {
            if !trendingStickerSets.isEmpty {
                sectionHeading("Featured Sticker Packs")
                LazyVStack(spacing: 8) {
                    ForEach(trendingStickerSets) { stickerSet in
                        TelegramStickerSetPickerRow(
                            stickerSet: stickerSet,
                            isInstalling: installingStickerSetId == stickerSet.id,
                            showsInstallButton: true,
                            onOpen: { selectedStickerSet = stickerSet },
                            onInstall: { install(stickerSet) },
                        )
                    }
                }
            }

            if !favoriteStickers.isEmpty {
                sectionHeading("Favorites")
                stickerGrid(favoriteStickers)
            }

            if !recentStickers.isEmpty {
                HStack {
                    sectionHeading("Recent")
                    Spacer()
                    Button("Clear", role: .destructive) {
                        showsClearRecentConfirmation = true
                    }
                    .confirmationDialog(
                        "Clear Recent Stickers?",
                        isPresented: $showsClearRecentConfirmation,
                    ) {
                        Button("Clear Recent Stickers", role: .destructive) {
                            Task { await clearRecentStickers() }
                        }
                    }
                }
                stickerGrid(recentStickers, allowsRemovingFromRecent: true)
            }

            if !stickerSets.isEmpty {
                sectionHeading("Sticker Packs")
                LazyVStack(spacing: 8) {
                    ForEach(stickerSets) { stickerSet in
                        TelegramStickerSetPickerRow(
                            stickerSet: stickerSet,
                            isInstalling: false,
                            showsInstallButton: false,
                            onOpen: { selectedStickerSet = stickerSet },
                            onInstall: {},
                        )
                    }
                }
            }

            if favoriteStickers.isEmpty,
               recentStickers.isEmpty,
               stickerSets.isEmpty,
               trendingStickerSets.isEmpty,
               feedbackMessage == nil
            {
                ContentUnavailableView(
                    "No Stickers",
                    systemImage: "face.smiling",
                    description: Text("Install a sticker pack in Telegram, or search for a sticker."),
                )
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder private var searchContent: some View {
        if isSearching {
            ProgressView("Searching stickers")
        } else if searchResults.isEmpty, feedbackMessage == nil {
            ContentUnavailableView.search(text: normalizedQuery)
                .frame(maxWidth: .infinity)
        } else if !searchResults.isEmpty {
            sectionHeading("Search Results")
            stickerGrid(searchResults)
        }
    }

    private func sectionHeading(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .accessibilityAddTraits(.isHeader)
    }

    private func stickerGrid(_ stickers: [Sticker], allowsRemovingFromRecent: Bool = false) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 76, maximum: 96), spacing: 12)],
            spacing: 12,
        ) {
            ForEach(stickers, id: \.sticker.id) { sticker in
                let presentation = TelegramStickerPresentation(sticker)
                Button {
                    send(sticker)
                } label: {
                    ZStack(alignment: .topTrailing) {
                        preview(sticker)
                            .accessibilityHidden(true)
                        if presentation.isPremium {
                            TelegramPremiumStickerBadge()
                        }
                        if sendingStickerFileId == sticker.sticker.id {
                            ProgressView()
                                .accessibilityHidden(true)
                        }
                    }
                    .frame(minHeight: 76)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(sendingStickerFileId != nil)
                .accessibilityLabel(presentation.pickerAccessibilityLabel(
                    packTitle: setTitles[sticker.setId],
                ))
                .contextMenu {
                    Button("Send Silently", systemImage: "bell.slash") {
                        send(sticker, disableNotification: true)
                    }

                    let isFavorite = favoriteStickerFileIds.contains(sticker.sticker.id)
                    Button(
                        isFavorite ? "Remove from Favorites" : "Add to Favorites",
                        systemImage: isFavorite ? "star.slash" : "star",
                    ) {
                        toggleFavorite(sticker)
                    }
                    .disabled(mutatingStickerFileId != nil)

                    if allowsRemovingFromRecent {
                        Button("Remove from Recent", systemImage: "trash", role: .destructive) {
                            removeFromRecent(sticker)
                        }
                        .disabled(mutatingStickerFileId != nil)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    @MainActor private func loadLibraryIfNeeded() async {
        guard !hasLoadedLibrary else { return }
        await loadLibrary(force: false)
    }

    @MainActor private func loadLibrary(force: Bool) async {
        guard force || !hasLoadedLibrary else { return }
        guard !isLoadingLibrary else { return }
        isLoadingLibrary = true
        feedbackMessage = nil
        feedbackIsFocused = false

        if hasPremium == nil, let currentUser = try? await service.getMe() {
            hasPremium = currentUser.isPremium
        }

        var errors = [String]()
        do {
            favoriteStickers = try await telegramUniqueStickers(
                service.getFavoriteStickers().stickers,
            )
        } catch {
            errors.append("Favorite stickers couldn't be loaded: \(telegramErrorDescription(error))")
        }

        guard !Task.isCancelled else {
            isLoadingLibrary = false
            return
        }

        do {
            recentStickers = try await telegramUniqueStickers(
                service.getRecentStickers(isAttached: false).stickers,
            )
        } catch {
            errors.append("Recent stickers couldn't be loaded: \(telegramErrorDescription(error))")
        }

        guard !Task.isCancelled else {
            isLoadingLibrary = false
            return
        }

        do {
            stickerSets = try await service.getInstalledStickerSets(stickerType: .stickerTypeRegular)
                .sets
                .filter(\.isInstalled)
        } catch {
            errors.append("Sticker packs couldn't be loaded: \(telegramErrorDescription(error))")
        }

        guard !Task.isCancelled else {
            isLoadingLibrary = false
            return
        }

        do {
            let trending = try await service.getTrendingStickerSets(
                limit: 20,
                offset: 0,
                stickerType: .stickerTypeRegular,
            )
            let installedIds = Set(stickerSets.map(\.id))
            trendingStickerSets = trending.sets.filter { !installedIds.contains($0.id) }
            let unseenIds = trendingStickerSets.filter { !$0.isViewed }.map(\.id)
            if !unseenIds.isEmpty {
                _ = try? await service.viewTrendingStickerSets(stickerSetIds: unseenIds)
            }
        } catch {
            // Featured packs are additive; installed, favorite, and recent stickers remain usable.
            trendingStickerSets = []
        }

        hasLoadedLibrary = true
        isLoadingLibrary = false
        if !errors.isEmpty {
            showFeedback(errors.joined(separator: " "))
        }
    }

    /// Merges two sources: `getStickers` (installed/recent/trending only) and `searchStickers`
    /// (the public catalog) - the latter is emoji-driven, not free text, so the typed query is
    /// resolved to matching emoji via `searchEmojis` first, the same way real Telegram clients do.
    /// Each source is allowed to fail independently so one flaky call doesn't blank out the other's
    /// results.
    @MainActor private func search() async {
        guard !normalizedQuery.isEmpty else {
            searchResults = []
            isSearching = false
            return
        }
        isSearching = true
        feedbackMessage = nil
        feedbackIsFocused = false

        async let installed = try? service.getStickers(
            chatId: chatId,
            limit: 100,
            query: normalizedQuery,
            stickerType: .stickerTypeRegular,
        )
        async let catalog = catalogSearch(query: normalizedQuery)
        let (installedResult, catalogResult) = await (installed, catalog)
        guard !Task.isCancelled else { return }

        searchResults = telegramUniqueStickers((installedResult?.stickers ?? []) + (catalogResult ?? []))
        isSearching = false
        if installedResult == nil, catalogResult == nil {
            showFeedback("Sticker search failed.")
        }
    }

    private func catalogSearch(query: String) async -> [Sticker]? {
        let resolvedEmojis = await (try? service.searchEmojis(inputLanguageCodes: nil, text: query))?
            .emojiKeywords
            .map(\.emoji)
            .joined(separator: " ") ?? ""
        return try? await service.searchStickers(
            emojis: resolvedEmojis,
            inputLanguageCodes: nil,
            limit: 50,
            offset: 0,
            query: query,
            stickerType: .stickerTypeRegular,
        )
        .stickers
    }

    private func send(_ sticker: Sticker, disableNotification: Bool = false) {
        guard sendingStickerFileId == nil else { return }
        if TelegramStickerPresentation(sticker).isPremium, hasPremium == false {
            showsPremiumRequiredAlert = true
            return
        }
        sendingStickerFileId = sticker.sticker.id
        feedbackMessage = nil
        feedbackIsFocused = false
        Task {
            do {
                try await TelegramStickerSending.send(
                    sticker,
                    service: service,
                    chatId: chatId,
                    replyToMessageId: replyToMessageId,
                    disableNotification: disableNotification,
                    topicId: topicId,
                )
                await onSent()
            } catch {
                showFeedback("Sticker couldn't be sent: \(telegramErrorDescription(error))")
            }
            sendingStickerFileId = nil
        }
    }

    private func toggleFavorite(_ sticker: Sticker) {
        guard mutatingStickerFileId == nil else { return }
        let fileId = sticker.sticker.id
        mutatingStickerFileId = fileId
        Task {
            do {
                if favoriteStickerFileIds.contains(fileId) {
                    _ = try await service.removeFavoriteSticker(sticker: .inputFileId(.init(id: fileId)))
                    favoriteStickers.removeAll { $0.sticker.id == fileId }
                } else {
                    _ = try await service.addFavoriteSticker(sticker: .inputFileId(.init(id: fileId)))
                    favoriteStickers = telegramUniqueStickers([sticker] + favoriteStickers)
                }
            } catch {
                showFeedback("Favorites couldn't be updated: \(telegramErrorDescription(error))")
            }
            mutatingStickerFileId = nil
        }
    }

    private func removeFromRecent(_ sticker: Sticker) {
        guard mutatingStickerFileId == nil else { return }
        let fileId = sticker.sticker.id
        mutatingStickerFileId = fileId
        Task {
            do {
                _ = try await service.removeRecentSticker(
                    isAttached: false,
                    sticker: .inputFileId(.init(id: fileId)),
                )
                recentStickers.removeAll { $0.sticker.id == fileId }
            } catch {
                showFeedback("The sticker couldn't be removed from Recent: \(telegramErrorDescription(error))")
            }
            mutatingStickerFileId = nil
        }
    }

    @MainActor private func clearRecentStickers() async {
        do {
            _ = try await service.clearRecentStickers(isAttached: false)
            recentStickers.removeAll()
        } catch {
            showFeedback("Recent stickers couldn't be cleared: \(telegramErrorDescription(error))")
        }
    }

    private func install(_ stickerSet: StickerSetInfo) {
        guard installingStickerSetId == nil else { return }
        installingStickerSetId = stickerSet.id
        Task {
            do {
                _ = try await service.changeStickerSet(
                    isArchived: false,
                    isInstalled: true,
                    setId: stickerSet.id,
                )
                await loadLibrary(force: true)
            } catch {
                showFeedback("\(stickerSet.title) couldn't be installed: \(telegramErrorDescription(error))")
            }
            installingStickerSetId = nil
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

// MARK: - TelegramStickerSetPickerView

private struct TelegramStickerSetPickerView<Preview: View>: View {
    // MARK: Internal

    let stickerSetInfo: StickerSetInfo
    let service: any TelegramService
    let sendingStickerFileId: Int?
    let favoriteStickerFileIds: Set<Int>
    let onBack: () -> Void
    let onSelect: (Sticker) -> Void
    let onSelectSilently: (Sticker) -> Void
    let onToggleFavorite: (Sticker) -> Void
    let preview: (Sticker) -> Preview

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Sticker Packs", systemImage: "chevron.left", action: onBack)
                Spacer()
                Text(stickerSetInfo.title)
                    .bold()
                    .accessibilityAddTraits(.isHeader)
            }
            .padding()

            Divider()

            Group {
                if let stickerSet {
                    ScrollView {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 76, maximum: 96), spacing: 12)],
                            spacing: 12,
                        ) {
                            ForEach(stickerSet.stickers, id: \.sticker.id) { sticker in
                                let presentation = TelegramStickerPresentation(sticker)
                                Button {
                                    onSelect(sticker)
                                } label: {
                                    ZStack(alignment: .topTrailing) {
                                        preview(sticker)
                                            .accessibilityHidden(true)
                                        if presentation.isPremium {
                                            TelegramPremiumStickerBadge()
                                        }
                                        if sendingStickerFileId == sticker.sticker.id {
                                            ProgressView()
                                                .accessibilityHidden(true)
                                        }
                                    }
                                    .frame(minHeight: 76)
                                    .contentShape(.rect)
                                }
                                .buttonStyle(.plain)
                                .disabled(sendingStickerFileId != nil)
                                .accessibilityLabel(presentation.pickerAccessibilityLabel(
                                    packTitle: stickerSet.title,
                                ))
                                .contextMenu {
                                    Button("Send Silently", systemImage: "bell.slash") {
                                        onSelectSilently(sticker)
                                    }

                                    let isFavorite = favoriteStickerFileIds.contains(sticker.sticker.id)
                                    Button(
                                        isFavorite ? "Remove from Favorites" : "Add to Favorites",
                                        systemImage: isFavorite ? "star.slash" : "star",
                                    ) {
                                        onToggleFavorite(sticker)
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                } else if let errorMessage {
                    ContentUnavailableView(
                        "Sticker Pack Unavailable",
                        systemImage: "exclamationmark.triangle",
                        description: Text(errorMessage),
                    )
                    .accessibilityFocused($errorIsFocused)
                } else {
                    ProgressView("Loading \(stickerSetInfo.title)")
                }
            }
        }
        .task(id: stickerSetInfo.id) { await loadStickerSet() }
    }

    // MARK: Private

    @AccessibilityFocusState private var errorIsFocused: Bool
    @State private var stickerSet: StickerSet?
    @State private var errorMessage: String?

    @MainActor private func loadStickerSet() async {
        do {
            let loadedStickerSet = try await service.getStickerSet(setId: stickerSetInfo.id)
            guard !Task.isCancelled else { return }
            stickerSet = loadedStickerSet
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = telegramErrorDescription(error)
            await Task.yield()
            errorIsFocused = true
        }
    }
}

// MARK: - TelegramPremiumStickerBadge

private struct TelegramPremiumStickerBadge: View {
    var body: some View {
        Image(systemName: "star.fill")
            .font(.caption2.bold())
            .foregroundStyle(.white)
            .padding(5)
            .background(Color.accentColor, in: Circle())
            .accessibilityHidden(true)
    }
}

// MARK: - TelegramStickerSendingError

private enum TelegramStickerSendingError: LocalizedError {
    case noMessageReturned

    // MARK: Internal

    var errorDescription: String? {
        "Telegram accepted the sticker but didn't return the sent message."
    }
}

func telegramUniqueStickers(_ stickers: [Sticker]) -> [Sticker] {
    var seenFileIds = Set<Int>()
    return stickers.filter { seenFileIds.insert($0.sticker.id).inserted }
}
