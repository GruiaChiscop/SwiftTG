// TelegramQrCodeImage.swift

import CoreImage
import CoreImage.CIFilterBuiltins

/// Renders a scannable QR code for a `tg://` login link (`authorizationStateWaitOtherDeviceConfirmation`),
/// using CoreImage directly - identical API on iOS and macOS, no third-party dependency.
func telegramQrCodeImage(for link: String) -> CGImage? {
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(link.utf8)
    filter.correctionLevel = "M"
    guard let outputImage = filter.outputImage else { return nil }
    let scaled = outputImage.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
    return CIContext().createCGImage(scaled, from: scaled.extent)
}
