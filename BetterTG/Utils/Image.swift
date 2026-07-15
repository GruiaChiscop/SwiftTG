// Image.swift

import ImageIO
import SwiftUI

func writeImage(_ uiImage: UIImage?, withSaving saving: Bool = false) -> SelectedImage? {
    guard let uiImage, let data = uiImage.jpegData(compressionQuality: 1) else { return nil }

    if saving {
        UIImageWriteToSavedPhotosAlbum(uiImage, nil, nil, nil)
    }

    let imageUrl = URL(filePath: NSTemporaryDirectory())
        .appending(path: "\(UUID().uuidString).jpeg")

    do {
        try data.write(to: imageUrl, options: .atomic)
        // Keep only a small preview in the observable composer state. The original
        // file remains untouched at `imageUrl` and is what TDLib uploads.
        let preview = downsampledImage(at: imageUrl, maxPixelSize: 320) ?? uiImage
        return SelectedImage(image: Image(uiImage: preview), url: imageUrl)
    } catch {
        log("Error getting data for an image: \(error)")
        return nil
    }
}

func downsampledImage(at url: URL, maxPixelSize: Int) -> UIImage? {
    guard maxPixelSize > 0,
          FileManager.default.fileExists(atPath: url.path),
          let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
              kCGImageSourceCreateThumbnailFromImageAlways: true,
              kCGImageSourceCreateThumbnailWithTransform: true,
              kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
              kCGImageSourceShouldCache: false,
              kCGImageSourceShouldCacheImmediately: true,
          ] as CFDictionary)
    else { return nil }

    return UIImage(cgImage: cgImage)
}

func imagePixelSize(at url: URL) -> CGSize? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
          let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue
    else { return nil }

    return CGSize(width: width, height: height)
}
