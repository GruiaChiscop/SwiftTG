// TelegramStickerAnimationView.swift

import CoreGraphics
import QuartzCore
import RLottieKit
import SwiftUI

#if os(iOS)
import UIKit

struct TelegramStickerAnimationView: UIViewRepresentable {
    let fileURL: URL
    let renderSize: CGSize
    let shouldPlay: Bool

    static func dismantleUIView(_ view: TelegramStickerAnimationSurfaceView, coordinator _: ()) {
        view.stop()
    }

    func makeUIView(context _: Context) -> TelegramStickerAnimationSurfaceView {
        TelegramStickerAnimationSurfaceView()
    }

    func updateUIView(_ view: TelegramStickerAnimationSurfaceView, context _: Context) {
        view.configure(fileURL: fileURL, renderSize: renderSize, shouldPlay: shouldPlay)
    }
}

@MainActor final class TelegramStickerAnimationSurfaceView: UIView {
    // MARK: Lifecycle

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        layer.contentsGravity = .resizeAspect
        self.displayLink = CADisplayLink(target: self, selector: #selector(displayLinkDidFire(_:)))
        displayLink?.add(to: .main, forMode: .common)
        displayLink?.isPaused = true
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        MainActor.assumeIsolated {
            displayLink?.invalidate()
            loadTask?.cancel()
            renderTask?.cancel()
        }
    }

    // MARK: Internal

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updatePlaybackState()
    }

    func configure(fileURL: URL, renderSize: CGSize, shouldPlay: Bool) {
        self.shouldPlay = shouldPlay
        let pixelSize = Self.boundedPixelSize(renderSize, scale: traitCollection.displayScale)
        guard loadedURL != fileURL || self.pixelSize != pixelSize else {
            updatePlaybackState()
            return
        }

        loadedURL = fileURL
        self.pixelSize = pixelSize
        loadAnimation(from: fileURL)
    }

    func stop() {
        displayLink?.isPaused = true
        loadTask?.cancel()
        renderTask?.cancel()
    }

    // MARK: Private

    private var displayLink: CADisplayLink?
    private var animation: LottieAnimation?
    private var loadedURL: URL?
    private var pixelSize = CGSize(width: 1, height: 1)
    private var frameIndex = 0
    private var shouldPlay = false
    private var loadGeneration: UInt = 0
    private var loadTask: Task<Void, Never>?
    private var renderTask: Task<Void, Never>?

    private static func boundedPixelSize(_ size: CGSize, scale: CGFloat) -> CGSize {
        let scale = min(max(1, scale), 2)
        let requestedWidth = max(1, size.width * scale)
        let requestedHeight = max(1, size.height * scale)
        let downscale = min(1, 448 / max(requestedWidth, requestedHeight))
        return CGSize(
            width: max(1, (requestedWidth * downscale).rounded()),
            height: max(1, (requestedHeight * downscale).rounded()),
        )
    }

    /// `@concurrent` (Swift 6.2) offloads this off the main actor while staying a structured child
    /// of `loadTask` - unlike `Task.detached`, `loadTask?.cancel()` (called on every re-configure
    /// and on `deinit`/`stop()`) actually reaches in here instead of only discarding the result
    /// after the decode finishes regardless.
    @concurrent private nonisolated static func loadAnimationConcurrently(from url: URL) async -> LottieAnimation? {
        LottieAnimation(tgsFileURL: url)
    }

    @concurrent private nonisolated static func renderFrameConcurrently(
        animation: LottieAnimation,
        index: Int,
        size: CGSize,
    ) async -> CGImage? {
        animation.renderFrame(index: index, size: size, scale: 1)
    }

    private func loadAnimation(from url: URL) {
        loadGeneration &+= 1
        let generation = loadGeneration
        loadTask?.cancel()
        renderTask?.cancel()
        animation = nil
        frameIndex = 0
        layer.contents = nil
        displayLink?.isPaused = true

        loadTask = Task { [weak self] in
            let animation = await Self.loadAnimationConcurrently(from: url)
            guard let self, generation == loadGeneration, !Task.isCancelled else { return }
            self.animation = animation
            configureDisplayRate()
            renderNextFrame()
            updatePlaybackState()
        }
    }

    private func configureDisplayRate() {
        guard let animation else { return }
        let framesPerSecond = Float(min(30, max(1, animation.frameRate)))
        displayLink?.preferredFrameRateRange = CAFrameRateRange(
            minimum: framesPerSecond,
            maximum: framesPerSecond,
            preferred: framesPerSecond,
        )
    }

    private func updatePlaybackState() {
        displayLink?.isPaused = animation == nil || !shouldPlay || window == nil
    }

    @objc private func displayLinkDidFire(_: CADisplayLink) {
        renderNextFrame()
    }

    private func renderNextFrame() {
        guard renderTask == nil, let animation else { return }
        let width = Int(pixelSize.width)
        let height = Int(pixelSize.height)
        let index = frameIndex
        let generation = loadGeneration
        frameIndex = (frameIndex + 1) % max(1, animation.frameCount)

        renderTask = Task { [weak self] in
            let image = await Self.renderFrameConcurrently(
                animation: animation,
                index: index,
                size: CGSize(width: CGFloat(width), height: CGFloat(height)),
            )
            guard let self else { return }
            defer { renderTask = nil }
            guard generation == loadGeneration, !Task.isCancelled else { return }
            layer.contents = image
        }
    }
}
#elseif os(macOS)
import AppKit

struct TelegramStickerAnimationView: NSViewRepresentable {
    let fileURL: URL
    let renderSize: CGSize
    let shouldPlay: Bool

    static func dismantleNSView(_ view: TelegramStickerAnimationSurfaceView, coordinator _: ()) {
        view.stop()
    }

    func makeNSView(context _: Context) -> TelegramStickerAnimationSurfaceView {
        TelegramStickerAnimationSurfaceView()
    }

    func updateNSView(_ view: TelegramStickerAnimationSurfaceView, context _: Context) {
        view.configure(fileURL: fileURL, renderSize: renderSize, shouldPlay: shouldPlay)
    }
}

@MainActor final class TelegramStickerAnimationSurfaceView: NSView {
    // MARK: Lifecycle

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.contentsGravity = .resizeAspect
        self.displayLink = displayLink(target: self, selector: #selector(displayLinkDidFire(_:)))
        displayLink?.add(to: .main, forMode: .common)
        displayLink?.isPaused = true
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        displayLink?.invalidate()
        loadTask?.cancel()
        renderTask?.cancel()
    }

    // MARK: Internal

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updatePlaybackState()
    }

    func configure(fileURL: URL, renderSize: CGSize, shouldPlay: Bool) {
        self.shouldPlay = shouldPlay
        let pixelSize = Self.boundedPixelSize(renderSize, scale: window?.backingScaleFactor ?? 2)
        guard loadedURL != fileURL || self.pixelSize != pixelSize else {
            updatePlaybackState()
            return
        }

        loadedURL = fileURL
        self.pixelSize = pixelSize
        loadAnimation(from: fileURL)
    }

    func stop() {
        displayLink?.isPaused = true
        loadTask?.cancel()
        renderTask?.cancel()
    }

    // MARK: Private

    private var displayLink: CADisplayLink?
    private var animation: LottieAnimation?
    private var loadedURL: URL?
    private var pixelSize = CGSize(width: 1, height: 1)
    private var frameIndex = 0
    private var shouldPlay = false
    private var loadGeneration: UInt = 0
    private var loadTask: Task<Void, Never>?
    private var renderTask: Task<Void, Never>?

    private static func boundedPixelSize(_ size: CGSize, scale: CGFloat) -> CGSize {
        let scale = min(max(1, scale), 2)
        let requestedWidth = max(1, size.width * scale)
        let requestedHeight = max(1, size.height * scale)
        let downscale = min(1, 448 / max(requestedWidth, requestedHeight))
        return CGSize(
            width: max(1, (requestedWidth * downscale).rounded()),
            height: max(1, (requestedHeight * downscale).rounded()),
        )
    }

    /// `@concurrent` (Swift 6.2) offloads this off the main actor while staying a structured child
    /// of `loadTask` - unlike `Task.detached`, `loadTask?.cancel()` (called on every re-configure
    /// and on `deinit`/`stop()`) actually reaches in here instead of only discarding the result
    /// after the decode finishes regardless.
    @concurrent private nonisolated static func loadAnimationConcurrently(from url: URL) async -> LottieAnimation? {
        LottieAnimation(tgsFileURL: url)
    }

    @concurrent private nonisolated static func renderFrameConcurrently(
        animation: LottieAnimation,
        index: Int,
        size: CGSize,
    ) async -> CGImage? {
        animation.renderFrame(index: index, size: size, scale: 1)
    }

    private func loadAnimation(from url: URL) {
        loadGeneration &+= 1
        let generation = loadGeneration
        loadTask?.cancel()
        renderTask?.cancel()
        animation = nil
        frameIndex = 0
        layer?.contents = nil
        displayLink?.isPaused = true

        loadTask = Task { [weak self] in
            let animation = await Self.loadAnimationConcurrently(from: url)
            guard let self, generation == loadGeneration, !Task.isCancelled else { return }
            self.animation = animation
            configureDisplayRate()
            renderNextFrame()
            updatePlaybackState()
        }
    }

    private func configureDisplayRate() {
        guard let animation else { return }
        let framesPerSecond = Float(min(30, max(1, animation.frameRate)))
        displayLink?.preferredFrameRateRange = CAFrameRateRange(
            minimum: framesPerSecond,
            maximum: framesPerSecond,
            preferred: framesPerSecond,
        )
    }

    private func updatePlaybackState() {
        displayLink?.isPaused = animation == nil || !shouldPlay || window == nil
    }

    @objc private func displayLinkDidFire(_: CADisplayLink) {
        renderNextFrame()
    }

    private func renderNextFrame() {
        guard renderTask == nil, let animation else { return }
        let width = Int(pixelSize.width)
        let height = Int(pixelSize.height)
        let index = frameIndex
        let generation = loadGeneration
        frameIndex = (frameIndex + 1) % max(1, animation.frameCount)

        renderTask = Task { [weak self] in
            let image = await Self.renderFrameConcurrently(
                animation: animation,
                index: index,
                size: CGSize(width: CGFloat(width), height: CGFloat(height)),
            )
            guard let self else { return }
            defer { renderTask = nil }
            guard generation == loadGeneration, !Task.isCancelled else { return }
            layer?.contents = image
        }
    }
}
#endif
