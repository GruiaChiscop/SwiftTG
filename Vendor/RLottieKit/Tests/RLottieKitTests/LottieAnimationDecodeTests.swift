import XCTest
@testable import RLottieKit
import CoreGraphics

final class LottieAnimationDecodeTests: XCTestCase {
    func testValidTgsLoads() throws {
        let url = Bundle.module.url(forResource: "tiny", withExtension: "tgs")!
        let animation = try XCTUnwrap(LottieAnimation(tgsFileURL: url))
        XCTAssertEqual(animation.dimensions, CGSize(width: 100, height: 100))
        XCTAssertEqual(animation.frameRate, 30)
        XCTAssertEqual(animation.frameCount, 30)
        XCTAssertEqual(animation.duration, 1.0, accuracy: 0.0001)
    }

    func testRandomBytesReturnsNil() throws {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("bogus-\(UUID().uuidString).tgs")
        let bogus = Data((0..<256).map { _ in UInt8.random(in: 0...255) })
        try bogus.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertNil(LottieAnimation(tgsFileURL: url))
    }

    func testRawJsonReturnsNil() throws {
        // We accept TGS (gzipped) only — raw JSON should fail the gunzip step.
        let url = Bundle.module.url(forResource: "tiny", withExtension: "json")!
        XCTAssertNil(LottieAnimation(tgsFileURL: url))
    }

    func testRenderFrameProducesNonEmptyImage() throws {
        let url = try visibleTgsURL()
        let animation = try XCTUnwrap(LottieAnimation(tgsFileURL: url))
        let image = animation.renderFrame(index: 0, size: CGSize(width: 32, height: 32), scale: 1.0)
        XCTAssertNotNil(image)
        XCTAssertEqual(image?.width, 32)
        XCTAssertEqual(image?.height, 32)

        let pixels = try XCTUnwrap(image?.dataProvider?.data as Data?)
        XCTAssertTrue(pixels.contains { $0 != 0 }, "Rendered sticker must contain visible pixels")
    }

    func testConcurrentAnimationsCanRenderFrames() throws {
        let url = try visibleTgsURL()
        let animations = try (0..<8).map { _ in
            try XCTUnwrap(LottieAnimation(tgsFileURL: url))
        }

        DispatchQueue.concurrentPerform(iterations: 64) { iteration in
            let animation = animations[iteration % animations.count]
            _ = animation.renderFrame(
                index: iteration % animation.frameCount,
                size: CGSize(width: 64, height: 64),
                scale: 1,
            )
        }

        XCTAssertNotNil(animations[0].renderFrame(index: 0, size: CGSize(width: 64, height: 64), scale: 1))
    }

    private func visibleTgsURL() throws -> URL {
        let base64 = "H4sIAAAAAAAAA3VSwU7EIBC9+xVmzmRDo1sTPsAPUG8bDthSt2lLEVDTNPy7M5RouqRJ6cAb3ps3E1b4BgHn09OpBgadA/HAGfQWBIbZbscfEBXHeM3RTMgJvVmQ0rZtuqu818GDuEgGo1q0o/36l+4NxopBWEA8ZoUX3d6/fn4pp1HHu5QfkLbCTD+ViEOqGRm4HUaI3SGXM2f4cYkZtc8guuF+j1MzeclItDml/FVZvdknu+Aa6jPZuxGoOauTsC0KysJyRZ5z401Q5mPUEFmu0Y1Yo7mxR7ZZRUoHA6my4HM/jv9awcGRo3Iwx2MpO+AHTvxQXPOqgJLTN6eM72Y3QZTFO/MhHd8nIsh49wuls23cnQIAAA=="
        let data = try XCTUnwrap(Data(base64Encoded: base64))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("visible-\(UUID().uuidString).tgs")
        try data.write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}
