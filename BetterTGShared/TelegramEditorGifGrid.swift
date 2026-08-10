// TelegramEditorGifGrid.swift

import SwiftUI
import TDLibKit

struct TelegramEditorGifGrid: View {
    // MARK: Internal

    let animations: [TDLibKit.Animation]
    let service: any TelegramService
    let selectingFileId: Int?
    let onSelect: (TDLibKit.Animation) -> Void

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 120, maximum: 160), spacing: 8)],
            spacing: 8,
        ) {
            ForEach(animations, id: \.animation.id) { animation in
                Button(action: { onSelect(animation) }) {
                    ZStack {
                        TelegramGifLoopingPreview(animation: animation, service: service)
                            .accessibilityHidden(true)
                        if selectingFileId == animation.animation.id {
                            ProgressView()
                                .accessibilityHidden(true)
                        }
                    }
                    .aspectRatio(aspectRatio(for: animation), contentMode: .fit)
                    .clipShape(.rect(cornerRadius: 10))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(selectingFileId != nil)
                .accessibilityLabel("GIF")
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: Private

    private func aspectRatio(for animation: TDLibKit.Animation) -> CGFloat {
        CGFloat(max(animation.width, 1)) / CGFloat(max(animation.height, 1))
    }
}
