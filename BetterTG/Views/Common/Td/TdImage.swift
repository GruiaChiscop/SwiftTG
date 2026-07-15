// TdImage.swift

import SwiftUI
import TDLibKit

struct TdImage: View {
    let photo: Photo
    let size: PhotoSizeType
    let contentMode: ContentMode
    var onLoad: (PhotoSize, File) -> Void = { _, _ in }
    
    var body: some View {
        if let size = photo.sizes.getSize(size) {
            AsyncTdImage(id: size.photo.id) { image, file in
                image
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .onAppear { onLoad(size, file) }
            } placeholder: {
                placeholder
            }
        } else {
            placeholder
        }
    }
    
    var placeholder: some View {
        Group {
            if let size = photo.sizes.getSize(.sBox) ?? photo.sizes.first {
                Image(file: size.photo)
                    .resizable()
            } else if let thumbnail = photo.minithumbnail {
                Image(data: thumbnail.data)?
                    .resizable()
            }
        }
        .aspectRatio(contentMode: contentMode)
        .blur(radius: 5)
    }
}

struct TdVideoThumbnail: View {
    let messageVideo: MessageVideo
    let contentMode: ContentMode

    var body: some View {
        if let cover = messageVideo.cover {
            TdImage(photo: cover, size: .xBox, contentMode: contentMode)
        } else if let thumbnail = messageVideo.video.thumbnail {
            AsyncTdImage(id: thumbnail.file.id) { image, _ in
                image
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } placeholder: {
                placeholder
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        Rectangle()
            .fill(.black.opacity(0.35))
            .overlay {
                Image(systemName: "video")
                    .foregroundStyle(.secondary)
            }
    }
}
