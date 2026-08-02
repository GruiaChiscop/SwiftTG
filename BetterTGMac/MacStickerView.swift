// MacStickerView.swift

import AppKit
import SwiftUI
import TDLibKit

struct MacStickerView: View {
    // MARK: Internal

    @Bindable var model: MacSessionModel

    let content: MessageSticker

    var body: some View {
        Group {
            switch presentation.kind {
            case .image:
                if let stickerImage {
                    Image(nsImage: stickerImage)
                        .resizable()
                        .scaledToFit()
                } else {
                    placeholder
                }
            case .vectorAnimation:
                if let stickerPath {
                    TelegramStickerAnimationView(
                        fileURL: URL(filePath: stickerPath),
                        renderSize: displaySize,
                        shouldPlay: isVisible && scenePhase == .active && !reduceMotion,
                    )
                } else {
                    placeholder
                }
            case .video:
                if let stickerPath {
                    TelegramStickerVideoView(
                        fileURL: URL(filePath: stickerPath),
                        shouldPlay: isVisible && scenePhase == .active && !reduceMotion,
                    )
                } else {
                    videoPreview
                }
            }
        }
        .frame(width: displaySize.width, height: displaySize.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
        .task(id: presentation.fileId) {
            guard let path = await model.localStickerPath(fileId: presentation.fileId)
            else { return }
            stickerPath = path
            if presentation.kind == .image {
                stickerImage = await Self.decodeImage(atPath: path)
            }
        }
        .task(id: presentation.thumbnailFileId) {
            guard let thumbnailFileId = presentation.thumbnailFileId,
                  let path = await model.localPhotoPath(fileId: thumbnailFileId)
            else { return }
            thumbnailImage = await Self.decodeImage(atPath: path)
        }
    }

    // MARK: Private

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var stickerPath: String?
    @State private var stickerImage: NSImage?
    @State private var thumbnailImage: NSImage?
    @State private var isVisible = false

    private var presentation: TelegramStickerPresentation {
        TelegramStickerPresentation(content)
    }

    private var displaySize: CGSize {
        presentation.displaySize()
    }

    @ViewBuilder private var placeholder: some View {
        if let thumbnailImage {
            Image(nsImage: thumbnailImage)
                .resizable()
                .scaledToFit()
        } else {
            ZStack {
                Color.secondary.opacity(0.08)
                ProgressView()
            }
            .clipShape(.rect(cornerRadius: 20))
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder private var videoPreview: some View {
        if presentation.thumbnailFileId != nil {
            placeholder
        } else {
            ZStack {
                Color.secondary.opacity(0.12)
                Text(presentation.emoji.isEmpty ? "Sticker" : presentation.emoji)
                    .font(presentation.emoji.isEmpty ? .caption : .system(size: 56))
                    .foregroundStyle(.secondary)
            }
            .clipShape(.rect(cornerRadius: 20))
        }
    }

    private static func decodeImage(atPath path: String) async -> NSImage? {
        await Task.detached(priority: .userInitiated) {
            NSImage(contentsOfFile: path)
        }.value
    }
}
