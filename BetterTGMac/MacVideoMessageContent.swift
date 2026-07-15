// MacVideoMessageContent.swift

import AppKit
import SwiftUI
import TDLibKit

struct MacVideoMessageContent: View {
    // MARK: Internal

    let content: MessageVideo
    let thumbnail: NSImage?
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 6) {
                if content.showCaptionAboveMedia, !content.caption.text.isEmpty {
                    caption
                }

                ZStack {
                    if let thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 360, maxHeight: 320)
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.black.opacity(0.35))
                            .frame(width: 280, height: 180)
                    }

                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.white)
                        .shadow(radius: 3)

                    Text(telegramClockDuration(content.video.duration))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.7), in: Capsule())
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(8)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))

                if !content.showCaptionAboveMedia, !content.caption.text.isEmpty {
                    caption
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityHidden(true)
    }

    // MARK: Private

    private var caption: some View {
        Text(content.caption.text)
            .textSelection(.enabled)
    }
}
