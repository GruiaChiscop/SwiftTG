// SharedMediaView.swift

import SwiftUI
import TDLibKit

// MARK: - SharedMediaView

struct SharedMediaView: View {
    // MARK: Lifecycle

    init(
        chatId: Int64,
        chatTitle: String,
        service: any TelegramService,
        onOpenMessage: @escaping (Int64) -> Void,
    ) {
        self.chatTitle = chatTitle
        self.service = service
        self.onOpenMessage = onOpenMessage
        self._store = State(initialValue: TelegramSharedMediaStore(chatId: chatId, service: service))
    }

    // MARK: Internal

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                tabBar
                Divider()
                content
            }
            .navigationTitle("Shared Media")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task(id: selection) { await store.load(selection) }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @State private var selection = TelegramSharedMediaCategory.media
    @State private var store: TelegramSharedMediaStore

    private let chatTitle: String
    private let service: any TelegramService
    private let onOpenMessage: (Int64) -> Void

    private var page: TelegramSharedMediaPage { store.page(for: selection) }

    private var tabBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(TelegramSharedMediaCategory.allCases) { category in
                    Button(category.title) { selection = category }
                        .buttonStyle(.plain)
                        .font(.subheadline.weight(selection == category ? .semibold : .regular))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .overlay(alignment: .bottom) {
                            if selection == category {
                                Capsule().fill(.tint).frame(height: 3)
                            }
                        }
                        .accessibilityAddTraits(selection == category ? .isSelected : [])
                }
            }
            .padding(.horizontal, 12)
        }
        .scrollIndicators(.hidden)
        .accessibilityLabel("Shared media categories")
    }

    @ViewBuilder private var content: some View {
        if !page.hasLoaded, page.isLoading {
            ProgressView("Loading \(selection.title.lowercased())…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = page.error, page.messages.isEmpty {
            ContentUnavailableView(
                "Couldn't Load \(selection.title)",
                systemImage: "exclamationmark.triangle",
                description: Text(error),
            )
            Button("Try Again") { Task { await store.load(selection, reset: true) } }
        } else if page.messages.isEmpty {
            ContentUnavailableView(
                "No \(selection.title)",
                systemImage: selection.systemImage,
                description: Text("No \(selection.title.lowercased()) were found in \(chatTitle)."),
            )
        } else if selection == .media {
            mediaGrid
        } else {
            itemList
        }
    }

    private var mediaGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 105), spacing: 2)], spacing: 2) {
                ForEach(page.messages, id: \.id) { message in
                    Button { onOpenMessage(message.id) } label: {
                        SharedMediaThumbnail(message: message, service: service)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        "\(telegramSharedMediaTitle(message)), \(telegramSharedMediaSubtitle(message))",
                    )
                    .onAppear { loadNextIfNeeded(message) }
                }
                loadingFooter
            }
            .padding(2)
        }
    }

    private var itemList: some View {
        List {
            ForEach(page.messages, id: \.id) { message in
                if selection == .links, let formattedText = telegramMessageFormattedText(message) {
                    let links = TelegramTextFormatting.links(in: formattedText)
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(links) { link in
                            Link(link.displayedText, destination: link.url)
                        }
                        Text(telegramSharedMediaSubtitle(message))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Button { onOpenMessage(message.id) } label: {
                        SharedMediaListLabel(message: message, category: selection)
                    }
                    .buttonStyle(.plain)
                }
            }
            loadingFooter
        }
        .listStyle(.plain)
    }

    @ViewBuilder private var loadingFooter: some View {
        if page.isLoading {
            ProgressView().frame(maxWidth: .infinity).padding()
        } else if page.hasMore {
            Color.clear.frame(height: 1).onAppear { Task { await store.load(selection) } }
        }
    }

    private func loadNextIfNeeded(_ message: Message) {
        guard page.messages.suffix(8).contains(where: { $0.id == message.id }) else { return }
        Task { await store.load(selection) }
    }
}

// MARK: - SharedMediaThumbnail

private struct SharedMediaThumbnail: View {
    let message: Message
    let service: any TelegramService

    var body: some View {
        ZStack {
            Rectangle().fill(Color.secondary.opacity(0.15))
            if let fileId = telegramSharedMediaThumbnailFileId(message) {
                AsyncTdImage(id: fileId, maxPixelSize: 360, service: service) { image, _ in
                    image.resizable().scaledToFill()
                } placeholder: {
                    ProgressView()
                }
            } else {
                Image(systemName: "photo")
            }
            if case .messageVideo = message.content {
                Image(systemName: "play.circle.fill")
                    .font(.title)
                    .foregroundStyle(.white)
                    .shadow(radius: 2)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipped()
        .accessibilityHidden(true)
    }
}

// MARK: - SharedMediaListLabel

private struct SharedMediaListLabel: View {
    let message: Message
    let category: TelegramSharedMediaCategory

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: category.systemImage)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(telegramSharedMediaTitle(message)).lineLimit(2)
                Text(telegramSharedMediaSubtitle(message))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
