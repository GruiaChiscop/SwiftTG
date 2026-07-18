// MacPhotoMessageContent.swift

import AppKit
import SwiftUI
import TDLibKit

struct MacPhotoMessageContent: View {
    let content: MessagePhoto
    let image: NSImage?
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: onOpen) {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 360, maxHeight: 320)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    ProgressView("Loading photo…")
                        .frame(minWidth: 180, minHeight: 100)
                }
            }
            .buttonStyle(.plain)
            .disabled(image == nil)
            .accessibilityHidden(true)
            if !content.caption.text.isEmpty {
                MacFormattedTextView(formattedText: content.caption)
            }
        }
    }
}
