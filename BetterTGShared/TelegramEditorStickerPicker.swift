// TelegramEditorStickerPicker.swift

import SwiftUI
import TDLibKit

struct TelegramEditorStickerPicker: View {
    // MARK: Internal

    let service: any TelegramService
    let onSelected: (TelegramStaticStickerOverlay) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if isLoading, stickers.isEmpty {
                    ProgressView("Loading stickers")
                } else if stickers.isEmpty, errorMessage == nil {
                    ContentUnavailableView(
                        "No Static Stickers",
                        systemImage: "photo.on.rectangle.angled",
                        description: Text("Favorite or recent WEBP stickers will appear here."),
                    )
                } else {
                    ScrollView {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 76, maximum: 104), spacing: 12)],
                            spacing: 12,
                        ) {
                            ForEach(stickers, id: \.sticker.id) { sticker in
                                Button(action: { select(sticker) }) {
                                    ZStack {
                                        TelegramStickerRasterPreview(sticker: sticker, service: service)
                                        if downloadingStickerID == sticker.sticker.id {
                                            ProgressView()
                                                .padding()
                                                .background(.regularMaterial, in: Circle())
                                        }
                                    }
                                    .frame(minHeight: 76)
                                }
                                .buttonStyle(.plain)
                                .disabled(downloadingStickerID != nil)
                                .accessibilityLabel(TelegramStickerPresentation(sticker).accessibilityLabel)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Add Sticker")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
            }
        }
        .task { await load() }
        .alert("Couldn't Load Stickers", isPresented: errorIsPresented) {} message: {
            Text(errorMessage ?? "")
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 480)
        #endif
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @State private var stickers = [Sticker]()
    @State private var isLoading = false
    @State private var downloadingStickerID: Int?
    @State private var errorMessage: String?

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    errorMessage = nil
                }
            },
        )
    }

    @MainActor private func load() async {
        guard stickers.isEmpty, !isLoading else { return }
        isLoading = true
        async let favoriteResult = try? service.getFavoriteStickers()
        async let recentResult = try? service.getRecentStickers(isAttached: false)
        let (favorites, recent) = await (favoriteResult, recentResult)
        guard !Task.isCancelled else { return }
        stickers = telegramUniqueStickers(
            (favorites?.stickers ?? []) + (recent?.stickers ?? []),
        ).filter(isStaticSticker)
        isLoading = false
        if favorites == nil, recent == nil {
            errorMessage = "Favorite and recent stickers couldn't be loaded."
        }
    }

    private func isStaticSticker(_ sticker: Sticker) -> Bool {
        if case .stickerFormatWebp = sticker.format {
            true
        } else {
            false
        }
    }

    private func select(_ sticker: Sticker) {
        guard downloadingStickerID == nil else { return }
        downloadingStickerID = sticker.sticker.id
        Task {
            do {
                let file = try await service.downloadFile(
                    fileId: sticker.sticker.id,
                    limit: 0,
                    offset: 0,
                    priority: 32,
                    synchronous: true,
                )
                guard file.local.isDownloadingCompleted, !file.local.path.isEmpty else {
                    throw TelegramGifEditorError.downloadFailed
                }
                onSelected(.init(
                    url: URL(filePath: file.local.path),
                    pixelWidth: sticker.width,
                    pixelHeight: sticker.height,
                ))
                dismiss()
            } catch is CancellationError {
                return
            } catch {
                errorMessage = telegramErrorDescription(error)
                downloadingStickerID = nil
            }
        }
    }
}
