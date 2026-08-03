// SelectedImage.swift

import SwiftUI
import TDLibKit

// MARK: - SelectedImage

struct SelectedImage: Identifiable {
    let id = UUID()
    var image: Image
    var url: URL
}

// MARK: Equatable

extension SelectedImage: Equatable {
    static func == (lhs: SelectedImage, rhs: SelectedImage) -> Bool {
        lhs.url == rhs.url
    }
}

// MARK: Transferable

extension SelectedImage: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { data in
            let imageUrl = TelegramOutgoingFileStaging.shared.imageFileURL(fileExtension: "png")
            try data.write(to: imageUrl, options: .atomic)

            guard let preview = downsampledImage(at: imageUrl, maxPixelSize: 320)
            else { throw Error(code: 0, message: "Error loading Image from data") }

            return SelectedImage(image: Image(uiImage: preview), url: imageUrl)
        }
    }
}
