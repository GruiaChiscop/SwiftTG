// TelegramStickerPicker.swift

import Combine
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
        schedulingState: MessageSchedulingState? = nil,
        topicId: MessageTopic? = nil,
    ) async throws -> Message {
        let messages = try await TelegramMessageSending.send(
            service: service,
            chatId: chatId,
            contents: [content(for: sticker)],
            replyTo: TelegramMessageSending.replyTo(messageId: replyToMessageId),
            schedulingState: schedulingState,
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
struct TelegramStickerPickerContent<Preview: View, ContextPreview: View>: View {
    // MARK: Internal

    let service: any TelegramService
    let chatId: Int64
    let replyToMessageId: Int64?
    let allowsSendWhenOnline: Bool
    let topicId: MessageTopic?
    let query: String
    let onSent: @MainActor () async -> Void
    let preview: (Sticker) -> Preview
    let contextPreview: (Sticker) -> ContextPreview

    var body: some View {
        Group {
            if let selectedStickerSet {
                TelegramStickerSetPickerView(
                    stickerSetInfo: selectedStickerSet,
                    service: service,
                    sendingStickerFileId: sendingStickerFileId,
                    favoriteStickerFileIds: favoriteStickerFileIds,
                    chatId: chatId,
                    topicId: topicId,
                    onBack: { self.selectedStickerSet = nil },
                    onSelect: { send($0) },
                    onSelectSilently: { send($0, disableNotification: true) },
                    onSchedule: { stickerToSchedule = TelegramScheduledSticker(sticker: $0) },
                    onToggleFavorite: toggleFavorite,
                    preview: preview,
                    contextPreview: contextPreview,
                )
            } else {
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
                .modifier(TelegramChoosingStickerActivityModifier(
                    service: service,
                    chatId: chatId,
                    topicId: topicId,
                ))
            }
        }
        .task { await loadLibraryIfNeeded() }
        .task(id: searchKey) { await search() }
        .onReceive(service.updatePublisher.compactMap(TelegramMediaLibraryUpdate.init)) { update in
            guard update.affectsStickers else { return }
            scheduleLiveRefresh()
        }
        .onChange(of: normalizedQuery) { _, newValue in
            if !newValue.isEmpty {
                selectedEmojiCategory = nil
            }
        }
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
        .sheet(item: $stickerToSchedule) { request in
            TelegramScheduleSendView(allowsSendWhenOnline: allowsSendWhenOnline) { state in
                send(request.sticker, schedulingState: state)
            }
        }
        .sheet(item: $selectedStickerPackReference) { reference in
            TelegramStickerPackPreview(
                reference: reference,
                service: service,
                chatId: chatId,
                onSelect: { send($0) },
                preview: preview,
            )
        }
        .onDisappear {
            liveRefreshTask?.cancel()
            liveRefreshTask = nil
        }
    }

    // MARK: Private

    @AccessibilityFocusState private var feedbackIsFocused: Bool
    @State private var favoriteStickers = [Sticker]()
    @State private var recentStickers = [Sticker]()
    @State private var peerStickerSet: StickerSet?
    @State private var stickerSets = [StickerSetInfo]()
    @State private var trendingStickerSets = [StickerSetInfo]()
    @State private var searchResults = [Sticker]()
    @State private var emojiCategories = [EmojiCategory]()
    @State private var selectedEmojiCategory: EmojiCategory?
    @State private var isLoadingLibrary = false
    @State private var isSearching = false
    @State private var liveRefreshTask: Task<Void, Never>?
    @State private var hasLoadedLibrary = false
    @State private var sendingStickerFileId: Int?
    @State private var feedbackMessage: String?
    @State private var hasPremium: Bool?
    @State private var showsPremiumRequiredAlert = false
    @State private var showsClearRecentConfirmation = false
    @State private var showsCreationComposer = false
    @State private var selectedStickerSet: StickerSetInfo?
    @State private var selectedStickerPackReference: TelegramStickerPackReference?
    @State private var installingStickerSetId: TdInt64?
    @State private var mutatingStickerFileId: Int?
    @State private var stickerToSchedule: TelegramScheduledSticker?

    private var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var searchKey: String {
        "\(normalizedQuery)|\(selectedEmojiCategory?.name ?? "")"
    }

    private var setTitles: [TdInt64: String] {
        var titles = [TdInt64: String]()
        for stickerSet in stickerSets + trendingStickerSets {
            titles[stickerSet.id] = stickerSet.title
        }
        if let peerStickerSet {
            titles[peerStickerSet.id] = peerStickerSet.title
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
            if let peerStickerSet, !peerStickerSet.stickers.isEmpty {
                sectionHeading("\(peerStickerSet.title) · Group Stickers")
                stickerGrid(peerStickerSet.stickers)
            }

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
               peerStickerSet == nil,
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
            if let selectedEmojiCategory {
                ContentUnavailableView(
                    "No Stickers",
                    systemImage: "face.smiling",
                    description: Text("No stickers were found in \(selectedEmojiCategory.name)."),
                )
                .frame(maxWidth: .infinity)
            } else {
                ContentUnavailableView.search(text: normalizedQuery)
                    .frame(maxWidth: .infinity)
            }
        } else if !searchResults.isEmpty {
            sectionHeading(selectedEmojiCategory?.name ?? "Search Results")
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
                let packReference = TelegramStickerPackReference(sticker: sticker)
                let isFavorite = favoriteStickerFileIds.contains(sticker.sticker.id)
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
                    if let packReference {
                        Button("View Sticker Pack", systemImage: "square.stack.3d.up") {
                            selectedStickerPackReference = packReference
                        }
                    }

                    Button("Send Silently", systemImage: "bell.slash") {
                        send(sticker, disableNotification: true)
                    }

                    Button("Schedule Send…", systemImage: "clock") {
                        stickerToSchedule = TelegramScheduledSticker(sticker: sticker)
                    }

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
                } preview: {
                    contextPreview(sticker)
                        .frame(width: 200, height: 200)
                }
                .accessibilityActions {
                    // SwiftUI presents custom actions in reverse declaration order.
                    if allowsRemovingFromRecent {
                        Button("Remove from Recent") { removeFromRecent(sticker) }
                            .disabled(mutatingStickerFileId != nil)
                    }
                    Button(isFavorite ? "Remove from Favorites" : "Add to Favorites") {
                        toggleFavorite(sticker)
                    }
                    .disabled(mutatingStickerFileId != nil)
                    Button("Send Later") {
                        stickerToSchedule = TelegramScheduledSticker(sticker: sticker)
                    }
                    Button("Send Silently") {
                        send(sticker, disableNotification: true)
                    }
                    if let packReference {
                        Button("View Sticker Pack") {
                            selectedStickerPackReference = packReference
                        }
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

    private func scheduleLiveRefresh() {
        liveRefreshTask?.cancel()
        liveRefreshTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(100))
                while isLoadingLibrary {
                    try await Task.sleep(for: .milliseconds(100))
                }
                await loadLibrary(force: true)
                guard !Task.isCancelled else { return }
                liveRefreshTask = nil
            } catch is CancellationError {
                return
            } catch {
                return
            }
        }
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

        if let categories = try? await service.getEmojiCategories(type: .emojiCategoryTypeRegularStickers) {
            emojiCategories = categories.categories.sorted { lhs, rhs in
                lhs.isGreeting && !rhs.isGreeting
            }
        }

        peerStickerSet =
            if let chat = try? await service.getChat(chatId: chatId),
            case .chatTypeSupergroup(let supergroup) = chat.type,
            let fullInfo = try? await service
                .getSupergroupFullInfo(supergroupId: supergroup.supergroupId),
                fullInfo.stickerSetId != 0
            {
                try? await service.getStickerSet(setId: fullInfo.stickerSetId)
            } else {
                nil
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
            recentStickers = try await telegramRecentStickers(
                service.getRecentStickers(isAttached: false).stickers,
                excluding: favoriteStickers,
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
        guard !normalizedQuery.isEmpty || selectedEmojiCategory != nil else {
            searchResults = []
            isSearching = false
            return
        }
        isSearching = true
        feedbackMessage = nil
        feedbackIsFocused = false

        if let selectedEmojiCategory, case .emojiCategorySourcePremium = selectedEmojiCategory.source {
            do {
                let premium = try await service.getPremiumStickers(limit: 100)
                searchResults = telegramUniqueStickers(premium.stickers)
                isSearching = false
            } catch {
                isSearching = false
                showFeedback("Premium stickers couldn't be loaded: \(telegramErrorDescription(error))")
            }
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
        async let catalog = catalogSearch(query: normalizedQuery, categoryEmojis: categoryEmojis)
        let (installedResult, catalogResult) = await (installed, catalog)
        guard !Task.isCancelled else { return }

        searchResults = telegramUniqueStickers((installedResult?.stickers ?? []) + (catalogResult ?? []))
        isSearching = false
        if installedResult == nil, catalogResult == nil {
            showFeedback("Sticker search failed.")
        }
    }

    private func catalogSearch(query: String, categoryEmojis: [String]) async -> [Sticker]? {
        let resolvedEmojis =
            if categoryEmojis.isEmpty {
                await (try? service.searchEmojis(inputLanguageCodes: nil, text: query))?
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
            query: query,
            stickerType: .stickerTypeRegular,
        )
        .stickers
    }

    private func send(
        _ sticker: Sticker,
        disableNotification: Bool = false,
        schedulingState: MessageSchedulingState? = nil,
    ) {
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
                    schedulingState: schedulingState,
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
                    recentStickers.removeAll { $0.sticker.id == fileId }
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

private struct TelegramStickerSetPickerView<Preview: View, ContextPreview: View>: View {
    // MARK: Internal

    let stickerSetInfo: StickerSetInfo
    let service: any TelegramService
    let sendingStickerFileId: Int?
    let favoriteStickerFileIds: Set<Int>
    let chatId: Int64
    let topicId: MessageTopic?
    let onBack: () -> Void
    let onSelect: (Sticker) -> Void
    let onSelectSilently: (Sticker) -> Void
    let onSchedule: (Sticker) -> Void
    let onToggleFavorite: (Sticker) -> Void
    let preview: (Sticker) -> Preview
    let contextPreview: (Sticker) -> ContextPreview

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

                                    Button("Schedule Send…", systemImage: "clock") {
                                        onSchedule(sticker)
                                    }

                                    let isFavorite = favoriteStickerFileIds.contains(sticker.sticker.id)
                                    Button(
                                        isFavorite ? "Remove from Favorites" : "Add to Favorites",
                                        systemImage: isFavorite ? "star.slash" : "star",
                                    ) {
                                        onToggleFavorite(sticker)
                                    }
                                } preview: {
                                    contextPreview(sticker)
                                        .frame(width: 200, height: 200)
                                }
                                .accessibilityAction(named: "Send Later") {
                                    onSchedule(sticker)
                                }
                            }
                        }
                        .padding()
                    }
                    .modifier(TelegramChoosingStickerActivityModifier(
                        service: service,
                        chatId: chatId,
                        topicId: topicId,
                    ))
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

func telegramRecentStickers(_ stickers: [Sticker], excluding favorites: [Sticker]) -> [Sticker] {
    let favoriteFileIds = Set(favorites.map(\.sticker.id))
    return telegramUniqueStickers(stickers).filter { !favoriteFileIds.contains($0.sticker.id) }
}
