// TelegramStickerView.swift

import SwiftUI
import TDLibKit

struct TelegramStickerView: View {
    // MARK: Lifecycle

    init(
        content: MessageSticker,
        service: any TelegramService,
        maxSide: CGFloat = 224,
        playsAnimation: Bool = true,
    ) {
        self.init(
            sticker: content.sticker,
            service: service,
            maxSide: maxSide,
            playsAnimation: playsAnimation,
        )
    }

    init(
        sticker: Sticker,
        service: any TelegramService,
        maxSide: CGFloat = 224,
        playsAnimation: Bool = true,
    ) {
        self.sticker = sticker
        self.service = service
        self.maxSide = maxSide
        self.playsAnimation = playsAnimation
    }

    // MARK: Internal

    let sticker: Sticker
    let service: any TelegramService
    let maxSide: CGFloat
    let playsAnimation: Bool

    var body: some View {
        Group {
            switch presentation.kind {
            case .image:
                AsyncTdImage(id: presentation.fileId, maxPixelSize: 448, service: service) { image, _ in
                    image
                        .resizable()
                        .scaledToFit()
                } placeholder: {
                    placeholder
                }
            case .vectorAnimation:
                if playsAnimation {
                    AsyncTdFile(id: presentation.fileId, service: service) { file in
                        TelegramStickerAnimationView(
                            fileURL: URL(filePath: file.local.path),
                            renderSize: displaySize,
                            shouldPlay: isVisible && scenePhase == .active && !reduceMotion,
                        )
                    } placeholder: {
                        placeholder
                    }
                } else {
                    placeholder
                }
            case .video:
                if playsAnimation {
                    AsyncTdFile(id: presentation.fileId, service: service) { file in
                        TelegramStickerVideoView(
                            fileURL: URL(filePath: file.local.path),
                            shouldPlay: isVisible && scenePhase == .active && !reduceMotion,
                        )
                    } placeholder: {
                        videoPreview
                    }
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
    }

    // MARK: Private

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var isVisible = false

    private var presentation: TelegramStickerPresentation {
        TelegramStickerPresentation(sticker)
    }

    private var displaySize: CGSize {
        presentation.displaySize(maxSide: maxSide)
    }

    @ViewBuilder private var placeholder: some View {
        if let thumbnailFileId = presentation.thumbnailFileId {
            AsyncTdImage(id: thumbnailFileId, maxPixelSize: 448, service: service) { image, _ in
                image
                    .resizable()
                    .scaledToFit()
            } placeholder: {
                loadingPlaceholder
            }
        } else {
            fallbackPreview
        }
    }

    private var loadingPlaceholder: some View {
        ZStack {
            Color.secondary.opacity(0.08)
            ProgressView()
        }
        .clipShape(.rect(cornerRadius: 20))
        .accessibilityHidden(true)
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

    private var fallbackPreview: some View {
        ZStack {
            Color.secondary.opacity(0.12)
            Text(presentation.emoji.isEmpty ? "Sticker" : presentation.emoji)
                .font(presentation.emoji.isEmpty ? .caption : .system(size: min(56, maxSide * 0.5)))
                .foregroundStyle(.secondary)
        }
        .clipShape(.rect(cornerRadius: 20))
    }
}
