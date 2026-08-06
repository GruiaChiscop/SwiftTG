// TelegramStickerVideoView.swift

import QuartzCore
import SwiftUI
import TelegramWebM

#if os(iOS)
import UIKit

struct TelegramStickerVideoView: UIViewRepresentable {
    let fileURL: URL
    let shouldPlay: Bool

    static func dismantleUIView(_ view: TelegramStickerVideoSurfaceView, coordinator _: ()) {
        view.stop()
    }

    func makeUIView(context _: Context) -> TelegramStickerVideoSurfaceView {
        TelegramStickerVideoSurfaceView()
    }

    func updateUIView(_ view: TelegramStickerVideoSurfaceView, context _: Context) {
        view.configure(fileURL: fileURL, shouldPlay: shouldPlay)
    }
}

@MainActor final class TelegramStickerVideoSurfaceView: UIView {
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
        displayLink?.invalidate()
        loadTask?.cancel()
        renderTask?.cancel()
    }

    // MARK: Internal

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updatePlaybackState()
    }

    func configure(fileURL: URL, shouldPlay: Bool) {
        self.shouldPlay = shouldPlay
        guard loadedURL != fileURL else {
            updatePlaybackState()
            return
        }
        loadedURL = fileURL
        loadAnimation(from: fileURL)
    }

    func stop() {
        displayLink?.isPaused = true
        loadTask?.cancel()
        renderTask?.cancel()
    }

    // MARK: Private

    private var displayLink: CADisplayLink?
    private var animation: WebMAnimation?
    private var loadedURL: URL?
    private var shouldPlay = false
    private var framesPerTick = 1.0
    private var frameAccumulator = 0.0
    private var loadGeneration: UInt = 0
    private var loadTask: Task<Void, Never>?
    private var renderTask: Task<Void, Never>?

    /// `@concurrent` (Swift 6.2) offloads this off the main actor while staying a structured child
    /// of `loadTask` - unlike `Task.detached`, `loadTask?.cancel()` (called on every re-configure
    /// and on `deinit`/`stop()`) actually reaches in here instead of only discarding the result
    /// after the decode finishes regardless.
    @concurrent private nonisolated static func loadAnimationConcurrently(from url: URL) async -> WebMAnimation? {
        try? WebMAnimation(fileURL: url)
    }

    @concurrent private nonisolated static func renderFramesConcurrently(
        animation: WebMAnimation,
        frameCount: Int,
    ) async -> CGImage? {
        var image: CGImage?
        for _ in 0..<frameCount {
            if let frame = animation.nextFrame() {
                image = frame
            } else if animation.restart() {
                image = animation.nextFrame()
            }
        }
        return image
    }

    private func loadAnimation(from url: URL) {
        loadGeneration &+= 1
        let generation = loadGeneration
        loadTask?.cancel()
        renderTask?.cancel()
        animation = nil
        layer.contents = nil
        displayLink?.isPaused = true

        loadTask = Task { [weak self] in
            let animation = await Self.loadAnimationConcurrently(from: url)
            guard let self, generation == loadGeneration, !Task.isCancelled else { return }
            self.animation = animation
            configureDisplayRate()
            renderNextFrame(frameCount: 1)
            updatePlaybackState()
        }
    }

    private func configureDisplayRate() {
        guard let animation else { return }
        let sourceRate = min(60, max(1, animation.frameRate))
        let displayRate = min(30, sourceRate)
        framesPerTick = sourceRate / displayRate
        frameAccumulator = 0
        displayLink?.preferredFrameRateRange = CAFrameRateRange(
            minimum: Float(displayRate),
            maximum: Float(displayRate),
            preferred: Float(displayRate),
        )
    }

    private func updatePlaybackState() {
        displayLink?.isPaused = animation == nil || !shouldPlay || window == nil
    }

    @objc private func displayLinkDidFire(_: CADisplayLink) {
        guard renderTask == nil else { return }
        frameAccumulator += framesPerTick
        let frameCount = max(1, Int(frameAccumulator))
        frameAccumulator -= Double(frameCount)
        renderNextFrame(frameCount: frameCount)
    }

    private func renderNextFrame(frameCount: Int) {
        guard renderTask == nil, let animation else { return }
        let generation = loadGeneration

        renderTask = Task { [weak self] in
            let image = await Self.renderFramesConcurrently(animation: animation, frameCount: frameCount)
            guard let self else { return }
            defer { renderTask = nil }
            guard generation == loadGeneration, !Task.isCancelled else { return }
            if let image {
                layer.contents = image
            }
        }
    }
}
#elseif os(macOS)
import AppKit

struct TelegramStickerVideoView: NSViewRepresentable {
    let fileURL: URL
    let shouldPlay: Bool

    static func dismantleNSView(_ view: TelegramStickerVideoSurfaceView, coordinator _: ()) {
        view.stop()
    }

    func makeNSView(context _: Context) -> TelegramStickerVideoSurfaceView {
        TelegramStickerVideoSurfaceView()
    }

    func updateNSView(_ view: TelegramStickerVideoSurfaceView, context _: Context) {
        view.configure(fileURL: fileURL, shouldPlay: shouldPlay)
    }
}

@MainActor final class TelegramStickerVideoSurfaceView: NSView {
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

    func configure(fileURL: URL, shouldPlay: Bool) {
        self.shouldPlay = shouldPlay
        guard loadedURL != fileURL else {
            updatePlaybackState()
            return
        }
        loadedURL = fileURL
        loadAnimation(from: fileURL)
    }

    func stop() {
        displayLink?.isPaused = true
        loadTask?.cancel()
        renderTask?.cancel()
    }

    // MARK: Private

    private var displayLink: CADisplayLink?
    private var animation: WebMAnimation?
    private var loadedURL: URL?
    private var shouldPlay = false
    private var framesPerTick = 1.0
    private var frameAccumulator = 0.0
    private var loadGeneration: UInt = 0
    private var loadTask: Task<Void, Never>?
    private var renderTask: Task<Void, Never>?

    /// `@concurrent` (Swift 6.2) offloads this off the main actor while staying a structured child
    /// of `loadTask` - unlike `Task.detached`, `loadTask?.cancel()` (called on every re-configure
    /// and on `deinit`/`stop()`) actually reaches in here instead of only discarding the result
    /// after the decode finishes regardless.
    @concurrent private nonisolated static func loadAnimationConcurrently(from url: URL) async -> WebMAnimation? {
        try? WebMAnimation(fileURL: url)
    }

    @concurrent private nonisolated static func renderFramesConcurrently(
        animation: WebMAnimation,
        frameCount: Int,
    ) async -> CGImage? {
        var image: CGImage?
        for _ in 0..<frameCount {
            if let frame = animation.nextFrame() {
                image = frame
            } else if animation.restart() {
                image = animation.nextFrame()
            }
        }
        return image
    }

    private func loadAnimation(from url: URL) {
        loadGeneration &+= 1
        let generation = loadGeneration
        loadTask?.cancel()
        renderTask?.cancel()
        animation = nil
        layer?.contents = nil
        displayLink?.isPaused = true

        loadTask = Task { [weak self] in
            let animation = await Self.loadAnimationConcurrently(from: url)
            guard let self, generation == loadGeneration, !Task.isCancelled else { return }
            self.animation = animation
            configureDisplayRate()
            renderNextFrame(frameCount: 1)
            updatePlaybackState()
        }
    }

    private func configureDisplayRate() {
        guard let animation else { return }
        let sourceRate = min(60, max(1, animation.frameRate))
        let displayRate = min(30, sourceRate)
        framesPerTick = sourceRate / displayRate
        frameAccumulator = 0
        displayLink?.preferredFrameRateRange = CAFrameRateRange(
            minimum: Float(displayRate),
            maximum: Float(displayRate),
            preferred: Float(displayRate),
        )
    }

    private func updatePlaybackState() {
        displayLink?.isPaused = animation == nil || !shouldPlay || window == nil
    }

    @objc private func displayLinkDidFire(_: CADisplayLink) {
        guard renderTask == nil else { return }
        frameAccumulator += framesPerTick
        let frameCount = max(1, Int(frameAccumulator))
        frameAccumulator -= Double(frameCount)
        renderNextFrame(frameCount: frameCount)
    }

    private func renderNextFrame(frameCount: Int) {
        guard renderTask == nil, let animation else { return }
        let generation = loadGeneration

        renderTask = Task { [weak self] in
            let image = await Self.renderFramesConcurrently(animation: animation, frameCount: frameCount)
            guard let self else { return }
            defer { renderTask = nil }
            guard generation == loadGeneration, !Task.isCancelled else { return }
            if let image {
                layer?.contents = image
            }
        }
    }
}
#endif
