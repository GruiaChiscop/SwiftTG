import CoreGraphics
import Foundation
import TelegramWebMCore

public enum WebMEncoderError: Error {
    case encodingFailed
    case invalidConfiguration
}

public final class WebMEncoder {
    public init(
        outputURL: URL,
        width: Int,
        height: Int,
        frameRate: Int,
        bitRate: Int = 240_000,
    ) throws {
        guard outputURL.isFileURL,
              width > 0,
              height > 0,
              width.isMultiple(of: 2),
              height.isMultiple(of: 2),
              let encoder = TelegramWebMEncoderCreate(
                  outputURL.path(percentEncoded: false),
                  Int32(width),
                  Int32(height),
                  Int32(frameRate),
                  Int64(bitRate),
              )
        else {
            throw WebMEncoderError.invalidConfiguration
        }

        self.encoder = encoder
        self.width = width
        self.height = height
        bytesPerRow = width * 4
    }

    deinit {
        TelegramWebMEncoderDestroy(encoder)
    }

    public func append(_ image: CGImage) throws {
        var pixels = Data(count: bytesPerRow * height)
        let rendered = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue |
                    CGBitmapInfo.byteOrder32Little.rawValue,
            ) else { return false }
            context.interpolationQuality = .high
            context.clear(CGRect(x: 0, y: 0, width: width, height: height))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard rendered,
              pixels.withUnsafeBytes({ buffer in
                  TelegramWebMEncoderAppendBGRAFrame(
                      encoder,
                      buffer.baseAddress?.assumingMemoryBound(to: UInt8.self),
                      bytesPerRow,
                  )
              })
        else {
            throw WebMEncoderError.encodingFailed
        }
    }

    public func finish() throws {
        guard TelegramWebMEncoderFinish(encoder) else {
            throw WebMEncoderError.encodingFailed
        }
    }

    private let encoder: OpaquePointer
    private let width: Int
    private let height: Int
    private let bytesPerRow: Int
}
