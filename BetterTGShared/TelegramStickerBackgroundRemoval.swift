// TelegramStickerBackgroundRemoval.swift

import CoreImage
import CoreImage.CIFilterBuiltins
import Vision

/// Cuts the main subject out of a photo, matching Telegram's own "Cut Out an Object" sticker-editor
/// feature - uses `VNGenerateForegroundInstanceMaskRequest` (Vision), the same on-device subject
/// segmentation Apple ships for Photos' "Lift Subject" feature, requiring no new dependency.
///
enum TelegramStickerBackgroundRemoval {
    enum Error: Swift.Error, LocalizedError {
        case noSubjectFound
        case renderingFailed

        // MARK: Internal

        var errorDescription: String? {
            switch self {
            case .noSubjectFound:
                "Couldn't find anything to cut out of this photo."
            case .renderingFailed:
                "Couldn't process this photo."
            }
        }
    }

    /// Synchronous and potentially slow (on-device ML inference) - call from a background task.
    static func removingBackground(from image: CGImage) throws -> CGImage {
        let maskImage = try foregroundAlphaMask(from: image)
        return try applyingMask(CIImage(cgImage: maskImage), to: CIImage(cgImage: image))
    }

    /// Produces a white alpha mask that can be edited with erase/restore strokes before it is
    /// applied to the source image.
    static func foregroundAlphaMask(from image: CGImage) throws -> CGImage {
        let inputImage = CIImage(cgImage: image)
        let handler = VNImageRequestHandler(ciImage: inputImage)
        let request = VNGenerateForegroundInstanceMaskRequest()
        try handler.perform([request])

        guard let result = request.results?.first, !result.allInstances.isEmpty else {
            throw Error.noSubjectFound
        }

        let maskPixelBuffer = try result.generateScaledMaskForImage(forInstances: result.allInstances, from: handler)
        let maskImage = CIImage(cvPixelBuffer: maskPixelBuffer)
        let whiteImage = CIImage(color: .white).cropped(to: inputImage.extent)
        return try applyingMask(maskImage, to: whiteImage)
    }

    /// Kept separate from Vision inference so the alpha-mask composition can be verified with a
    /// deterministic unit test on every supported platform.
    static func applyingMask(_ maskImage: CIImage, to inputImage: CIImage) throws -> CGImage {
        let filter = CIFilter.blendWithMask()
        filter.inputImage = inputImage
        filter.maskImage = maskImage
        filter.backgroundImage = CIImage(color: .clear).cropped(to: inputImage.extent)

        guard let outputImage = filter.outputImage,
              let outputCGImage = CIContext().createCGImage(outputImage, from: inputImage.extent)
        else {
            throw Error.renderingFailed
        }
        return outputCGImage
    }
}
