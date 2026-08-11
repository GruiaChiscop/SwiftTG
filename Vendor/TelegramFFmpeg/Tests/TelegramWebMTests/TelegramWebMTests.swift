import CoreGraphics
import Foundation
import Testing
@testable import TelegramWebM

@Suite("Telegram WebM")
struct TelegramWebMTests {
    @Test("Encodes and decodes VP9 alpha frames")
    func encodesSyntheticAlphaWebM() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appendingPathExtension("webm")
        defer { try? FileManager.default.removeItem(at: url) }
        let first = try #require(Self.image(red: 1, alpha: 0.5))
        let second = try #require(Self.image(red: 0, alpha: 1))

        let encoder = try WebMEncoder(outputURL: url, width: 32, height: 32, frameRate: 4)
        try encoder.append(first)
        try encoder.append(second)
        try encoder.finish()

        let animation = try WebMAnimation(fileURL: url)
        let firstData = try #require(animation.nextFrameData())
        let secondData = try #require(animation.nextFrameData())
        let alphaValues = stride(from: 3, to: firstData.count, by: 4).map { firstData[$0] }

        #expect(animation.width == 32)
        #expect(animation.height == 32)
        #expect(animation.frameRate == 4)
        #expect(alphaValues.contains { $0 > 0 && $0 < 255 })
        #expect(firstData != secondData)
    }

    @Test("Decodes moving VP9 alpha frames")
    func decodesSyntheticAlphaWebM() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appendingPathExtension("webm")
        try #require(Data(base64Encoded: Self.alphaFixture)).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let animation = try WebMAnimation(fileURL: url)
        var frames: [Data] = []
        while let frame = animation.nextFrameData() {
            frames.append(frame)
        }

        #expect(frames.count == 4)
        let firstFrame = try #require(frames.first)
        let alphaValues = stride(from: 3, to: firstFrame.count, by: 4).map { firstFrame[$0] }
        let colorValues = firstFrame.enumerated().compactMap { index, value in
            index % 4 == 3 ? nil : value
        }
        #expect(alphaValues.contains { $0 > 0 && $0 < 255 })
        #expect(colorValues.contains { $0 != 0 })
        #expect(frames[0] != frames[1])

        #expect(animation.restart())
        #expect(animation.nextFrameData() == firstFrame)
    }

    @Test("Decodes Telegram's VP9 alpha sample")
    func decodesTelegramAlphaSampleWhenAvailable() throws {
        let packageRoot = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = packageRoot
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Telegram-iOS/Telegram/WatchApp/Assets/SampleStickers/sticker_vp9.webm")
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        let animation = try WebMAnimation(fileURL: url)
        let frame = try #require(animation.nextFrameData())
        let alphaValues = stride(from: 3, to: frame.count, by: 4).map { frame[$0] }
        let colorValues = frame.enumerated().compactMap { index, value in
            index % 4 == 3 ? nil : value
        }
        #expect(alphaValues.contains { $0 > 0 && $0 < 255 })
        #expect(colorValues.contains { $0 != 0 })
    }

    @Test("Decodes and restarts a VP9 WebM")
    func decodesWebM() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appendingPathExtension("webm")
        try #require(Data(base64Encoded: Self.fixture)).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let animation = try WebMAnimation(fileURL: url)
        #expect(animation.width == 32)
        #expect(animation.height == 32)
        #expect(animation.frameRate == 4)

        var frames: [Data] = []
        while let frame = animation.nextFrameData() {
            frames.append(frame)
        }
        #expect(frames.count == 2)
        let firstFrame = try #require(frames.first)
        let colorValues = firstFrame.enumerated().compactMap { index, value in
            index % 4 == 3 ? nil : value
        }
        #expect(colorValues.contains { $0 != 0 })

        #expect(animation.restart())
        #expect(animation.nextFrame() != nil)
    }

    @Test("Rejects non-WebM files")
    func rejectsInvalidFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appendingPathExtension("webm")
        try Data("not a webm file".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: WebMAnimationError.self) {
            try WebMAnimation(fileURL: url)
        }
    }

    private static let fixture = """
    GkXfo59ChoEBQveBAULygQRC84EIQoKEd2VibUKHgQJChYECGFOAZwEAAAAAAAI9EU2bdLpNu4tTq4QVSalmU6yBoU27i1OrhBZUrmtTrIHYTbuMU6uEElTDZ1OsggElTbuMU6uEHFO7a1OsggIn7AEAAAAAAABZAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAVSalmsirXsYMPQkBNgI1MYXZmNjIuMTIuMTAyV0GNTGF2ZjYyLjEyLjEwMkSJiEB/QAAAAAAAFlSua8iuAQAAAAAAAD/XgQFzxYia7vRFaoL7a5yBACK1nIN1bmSIgQCGhVZfVlA5g4EBI+ODhA7msoDgkLCBILqBIJqBAlWwhFW5gQESVMNnQIBzc6BjwIBnyJpFo4dFTkNPREVSRIeNTGF2ZjYyLjEyLjEwMnNz2mPAi2PFiJru9EVqgvtrZ8ilRaOHRU5DT0RFUkSHmExhdmM2Mi4yOC4xMDIgbGlidnB4LXZwOWfIoUWjiERVUkFUSU9ORIeTMDA6MDA6MDAuNTAwMDAwMDAwAB9DtnX354EAo96BAACAgkmDQgAB8AH2ADgkHBgAAADQfY69o8D+jqpxDvTAAHSeYMYZT64/ZdOU/E/t1H8jm1hXMHp8BUcrx2tSq7JXvU5448s1AsAlHkqVqe2iFe6eWf5RASjxWn0Ao5KBAPoAhgBAkpwAQAAAAgAAQ0AcU7trkbuPs4EAt4r3gQHxggGr8IED
    """

    private static func image(red: CGFloat, alpha: CGFloat) -> CGImage? {
        let side = 32
        guard let context = CGContext(
            data: nil,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        ) else { return nil }
        context.setFillColor(red: red, green: 0.25, blue: 0.5, alpha: alpha)
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        return context.makeImage()
    }

    private static let alphaFixture = """
    GkXfo59ChoEBQveBAULygQRC84EIQoKEd2VibUKHgQJChYECGFOAZwEAAAAAAAMqEU2bdLpNu4tTq4QVSalmU6yBoU27i1OrhBZUrmtTrIHYTbuMU6uEElTDZ1OsggEpTbuMU6uEHFO7a1OsggMU7AEAAAAAAABZAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAVSalmsirXsYMPQkBNgI1MYXZmNjIuMTIuMTAyV0GNTGF2ZjYyLjEyLjEwMkSJiECPQAAAAAAAFlSua8yuAQAAAAAAAEPXgQFzxYjuVD54NLGPs5yBACK1nIN1bmSIgQCGhVZfVlA5g4EBI+ODhA7msoDglLCBILqBIJqBAlPAgQFVsIRVuYEBElTDZ0CAc3OgY8CAZ8iaRaOHRU5DT0RFUkSHjUxhdmY2Mi4xMi4xMDJzc9pjwItjxYjuVD54NLGPs2fIpUWjh0VOQ09ERVJEh5hMYXZjNjIuMjguMTAyIGxpYnZweC12cDlnyKFFo4hEVVJBVElPTkSHkzAwOjAwOjAxLjAwMDAwMDAwMAAfQ7Z1QV/ngQCgQImhsIEAAACCSYNCAAHwAfYAOCQcGAAAACAAAF8////ka8AY////9n5Dh////7ZGAZmkAHWh1KbS7oEBpc2CSYNCAAHwAfYAOCQcGAAAACAAAB8////91fiAMv///4ekfo7uFP///nJeOU4G/65i/qE30MPG6jiBAKL///7lAfo27/8JN+LEAAAAAKDooZKBAPoAhgBAkpwAQAAAAgAAQ0B1oc2my+6BAaXGhgBAkpwAQAAAAgAAfqLan///+z7ntpPqMfxr3/BE3fJ9b4mnTkDLWoDdP///7nM/sf/J/9ZKh/IOVauDHIzFq9hL3Oc4APuC/wagsqGSgQH0AIYAQJKcAEAAAAIAAENAdaGXppXugQGlkIYAQJKcAEAAAAIAAEyh8ID7gv8GoLChkoEC7gCGAECSnABAAAACAABDQHWhlaaT7oEBpY6GAECSnABAAAACAABDQPuC/wYcU7trkbuPs4EAt4r3gQHxggGv8IED
    """
}
