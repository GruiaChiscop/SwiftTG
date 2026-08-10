// TelegramMediaEffectsRendering.swift

import CoreImage

enum TelegramMediaEffectsRendering {
    static func apply(_ effects: TelegramMediaEffects, to source: CIImage) -> CIImage {
        var output = source
        if effects.brightness != 0 || effects.contrast != 1 || effects.saturation != 1 {
            output = output.applyingFilter(
                "CIColorControls",
                parameters: [
                    kCIInputBrightnessKey: effects.brightness,
                    kCIInputContrastKey: effects.contrast,
                    kCIInputSaturationKey: effects.saturation,
                ],
            )
        }
        if effects.blurRadius > 0 {
            output = output
                .clampedToExtent()
                .applyingGaussianBlur(sigma: effects.blurRadius)
                .cropped(to: source.extent)
        }
        return output
    }
}
