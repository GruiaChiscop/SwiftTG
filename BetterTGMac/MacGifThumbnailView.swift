// MacGifThumbnailView.swift

import AppKit
import SwiftUI
import TDLibKit

/// Static thumbnail for a GIF picker grid cell - mirrors `MacSharedMediaThumbnail`'s
/// download-then-`NSImage`-decode pattern, since there's no Mac equivalent of iOS's
/// `AsyncTdImage` to reuse directly.
struct MacGifThumbnailView: View {
    // MARK: Internal

    @Bindable var model: MacSessionModel

    let animation: TDLibKit.Animation

    var body: some View {
        ZStack {
            Rectangle().fill(Color.secondary.opacity(0.15))
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: animation.thumbnail?.file.id) {
            guard let fileId = animation.thumbnail?.file.id,
                  let path = await model.localPhotoPath(fileId: fileId)
            else { return }
            image = NSImage(contentsOfFile: path)
        }
    }

    // MARK: Private

    @State private var image: NSImage?
}
