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
    ) async throws -> Message {
        let messages = try await TelegramMessageSending.send(
            service: service,
            chatId: chatId,
            contents: [content(for: sticker)],
            replyTo: TelegramMessageSending.replyTo(messageId: replyToMessageId),
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

// MARK: - TelegramStickerPickerView

struct TelegramStickerPickerView<Preview: View>: View {
    // MARK: Lifecycle

    init(
        service: any TelegramService,
        chatId: Int64,
        replyToMessageId: Int64?,
        onSent: @escaping @MainActor () async -> Void,
        @ViewBuilder preview: @escaping (Sticker) -> Preview,
    ) {
        self.service = service
        self.chatId = chatId
        self.replyToMessageId = replyToMessageId
        self.onSent = onSent
        self.preview = preview
    }

    // MARK: Internal

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    if normalizedQuery.isEmpty {
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
            .navigationTitle("Stickers")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .searchable(text: $query, prompt: "Search stickers")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button("Create Sticker") { showsCreationComposer = true }
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
    }

    // MARK: Private

    @AccessibilityFocusState private var feedbackIsFocused: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var recentStickers = [Sticker]()
    @State private var stickerSets = [StickerSetInfo]()
    @State private var searchResults = [Sticker]()
    @State private var isLoadingLibrary = false
    @State private var isSearching = false
    @State private var hasLoadedLibrary = false
    @State private var sendingStickerFileId: Int?
    @State private var feedbackMessage: String?
    @State private var hasPremium: Bool?
    @State private var showsPremiumRequiredAlert = false
    @State private var showsCreationComposer = false

    private let service: any TelegramService
    private let chatId: Int64
    private let replyToMessageId: Int64?
    private let onSent: @MainActor () async -> Void
    private let preview: (Sticker) -> Preview

    private var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var setTitles: [TdInt64: String] {
        Dictionary(uniqueKeysWithValues: stickerSets.map { ($0.id, $0.title) })
    }

    @ViewBuilder private var libraryContent: some View {
        if isLoadingLibrary, !hasLoadedLibrary {
            ProgressView("Loading stickers")
        } else {
            if !recentStickers.isEmpty {
                sectionHeading("Recent")
                stickerGrid(recentStickers)
            }

            if !stickerSets.isEmpty {
                sectionHeading("Sticker Packs")
                LazyVStack(spacing: 8) {
                    ForEach(stickerSets) { stickerSet in
                        NavigationLink {
                            TelegramStickerSetPickerView(
                                stickerSetInfo: stickerSet,
                                service: service,
                                sendingStickerFileId: sendingStickerFileId,
                                onSelect: send,
                                preview: preview,
                            )
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(stickerSet.title)
                                    Text("\(stickerSet.size) stickers")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.secondary)
                                    .accessibilityHidden(true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if recentStickers.isEmpty, stickerSets.isEmpty, feedbackMessage == nil {
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

    private func stickerGrid(_ stickers: [Sticker]) -> some View {
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

        hasLoadedLibrary = true
        isLoadingLibrary = false
        if !errors.isEmpty {
            showFeedback(errors.joined(separator: " "))
        }
    }

    @MainActor private func search() async {
        guard !normalizedQuery.isEmpty else {
            searchResults = []
            isSearching = false
            return
        }
        isSearching = true
        feedbackMessage = nil
        feedbackIsFocused = false
        do {
            let result = try await service.getStickers(
                chatId: chatId,
                limit: 100,
                query: normalizedQuery,
                stickerType: .stickerTypeRegular,
            )
            guard !Task.isCancelled else { return }
            searchResults = telegramUniqueStickers(result.stickers)
            isSearching = false
        } catch {
            guard !Task.isCancelled else { return }
            searchResults = []
            isSearching = false
            showFeedback("Sticker search failed: \(telegramErrorDescription(error))")
        }
    }

    private func send(_ sticker: Sticker) {
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
                )
                await onSent()
                dismiss()
            } catch {
                showFeedback("Sticker couldn't be sent: \(telegramErrorDescription(error))")
            }
            sendingStickerFileId = nil
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
    let onSelect: (Sticker) -> Void
    let preview: (Sticker) -> Preview

    var body: some View {
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
        .navigationTitle(stickerSetInfo.title)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
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
