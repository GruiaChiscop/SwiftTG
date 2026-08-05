// TelegramStickerBackgroundRemoval.swift

import CoreImage
import CoreImage.CIFilterBuiltins
import Vision

/// Cuts the main subject out of a photo, matching Telegram's own "Cut Out an Object" sticker-editor
/// feature - uses `VNGenerateForegroundInstanceMaskRequest` (Vision), the same on-device subject
/// segmentation Apple ships for Photos' "Lift Subject" feature, requiring no new dependency.
///
/// Important: this Vision request is not supported on the CPU-only execution path the iOS
/// Simulator uses - Apple's own docs state it "will not run in the simulator" and must be tested on
/// a physical device. There is no way to verify this function's actual output from this
/// environment; only that it compiles.
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
        let inputImage = CIImage(cgImage: image)
        let handler = VNImageRequestHandler(ciImage: inputImage)
        let request = VNGenerateForegroundInstanceMaskRequest()
        try handler.perform([request])

        guard let result = request.results?.first, !result.allInstances.isEmpty else {
            throw Error.noSubjectFound
        }

        let maskPixelBuffer = try result.generateScaledMaskForImage(forInstances: result.allInstances, from: handler)
        let maskImage = CIImage(cvPixelBuffer: maskPixelBuffer)

        let filter = CIFilter.blendWithMask()
        filter.inputImage = inputImage
        filter.maskImage = maskImage
        filter.backgroundImage = CIImage.empty()

        guard let outputImage = filter.outputImage,
              let outputCGImage = CIContext().createCGImage(outputImage, from: inputImage.extent)
        else {
            throw Error.renderingFailed
        }
        return outputCGImage
    }
}
