// MacGifMessageContent.swift

import AppKit
import SwiftUI
import TDLibKit

struct MacGifMessageContent: View {
    // MARK: Internal

    let content: MessageAnimation
    let thumbnail: NSImage?
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if content.showCaptionAboveMedia, !content.caption.text.isEmpty {
                caption
            }

            Button(action: onOpen) {
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

                    Text("GIF")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.7), in: Capsule())
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(8)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)

            if !content.showCaptionAboveMedia, !content.caption.text.isEmpty {
                caption
            }
        }
    }

    // MARK: Private

    private var caption: some View {
        MacFormattedTextView(formattedText: content.caption)
    }
}
