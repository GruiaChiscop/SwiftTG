// AttachmentStaging.swift

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Pixel dimensions of an image file, read directly from its metadata (no full decode) - used when
/// building the `width`/`height` TDLib expects for an outgoing photo message.
func imagePixelSize(at url: URL) -> CGSize? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
          let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue
    else { return nil }

    return CGSize(width: width, height: height)
}

/// Whether `url` refers to an image file - used to decide whether a batch of staged attachments
/// (pasted or picked together) should be sent as photos or as generic documents.
func isImageAttachment(_ url: URL) -> Bool {
    let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType
    guard let type = type ?? UTType(filenameExtension: url.pathExtension) else { return false }
    return type.conforms(to: .image)
}
