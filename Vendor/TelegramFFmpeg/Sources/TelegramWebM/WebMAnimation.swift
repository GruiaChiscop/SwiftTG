import CoreGraphics
import Foundation
import TelegramWebMCore

public enum WebMAnimationError: Error {
    case invalidFile
}

public final class WebMAnimation: @unchecked Sendable {
    public let width: Int
    public let height: Int
    public let frameRate: Double
    public let duration: Double

    public init(fileURL: URL) throws {
        guard fileURL.isFileURL,
              let decoder = TelegramWebMDecoderCreate(fileURL.path(percentEncoded: false))
        else {
            throw WebMAnimationError.invalidFile
        }

        self.decoder = decoder
        width = Int(TelegramWebMDecoderGetWidth(decoder))
        height = Int(TelegramWebMDecoderGetHeight(decoder))
        frameRate = TelegramWebMDecoderGetFrameRate(decoder)
        duration = TelegramWebMDecoderGetDuration(decoder)
        bytesPerRow = width * 4
        colorSpace = CGColorSpaceCreateDeviceRGB()
    }

    deinit {
        TelegramWebMDecoderDestroy(decoder)
    }

    public func nextFrame() -> CGImage? {
        guard let pixels = nextFrameData(),
              let provider = CGDataProvider(data: pixels as CFData)
        else {
            return nil
        }

        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue:
                CGImageAlphaInfo.premultipliedFirst.rawValue |
                    CGBitmapInfo.byteOrder32Little.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }

    func nextFrameData() -> Data? {
        var pixels = Data(count: bytesPerRow * height)
        let status = pixels.withUnsafeMutableBytes { buffer in
            TelegramWebMDecoderRenderNextFrame(
                decoder,
                buffer.baseAddress?.assumingMemoryBound(to: UInt8.self),
                bytesPerRow,
                nil
            )
        }
        return status == TelegramWebMFrameStatusFrame ? pixels : nil
    }

    @discardableResult public func restart() -> Bool {
        TelegramWebMDecoderRestart(decoder)
    }

    private let decoder: OpaquePointer
    private let bytesPerRow: Int
    private let colorSpace: CGColorSpace
}
