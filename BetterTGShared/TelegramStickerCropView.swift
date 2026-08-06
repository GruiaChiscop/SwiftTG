// TelegramStickerCropView.swift

import SwiftUI

/// Crops `sourceImage` to a Telegram-compliant sticker size and hands back the encoded PNG.
///
/// Matches Telegram's own crop tool (`TGPhotoCropController`): pinch/pan to reposition and zoom,
/// an aspect-ratio choice (Square or Original, matching its Square/Original presets), plus
/// Rotate/Mirror/Reset, and a Remove Background action (`TelegramStickerBackgroundRemoval`),
/// matching its "Cut Out an Object" tool. The rendered output follows Telegram's actual documented requirement
/// (core.telegram.org/stickers) - "one side must be exactly 512 pixels, the other side can be 512
/// pixels or less" - so a sticker is not forced to be square unless the Square ratio is chosen.
/// Also offers a set of discrete VoiceOver-adjustable controls alongside the gestures, since
/// pinch/pan aren't reliably operable through VoiceOver. Works directly in `CGImage` (rather than
/// `UIImage`/`NSImage`) so this stays cross-platform without any conditional compilation for the
/// image type itself.
struct TelegramStickerCropView: View {
    // MARK: Lifecycle

    init(sourceImage: CGImage, onCropped: @escaping (Data) -> Void, onChooseDifferentPhoto: @escaping () -> Void) {
        self.sourceImage = sourceImage
        _currentImage = State(initialValue: sourceImage)
        self.onCropped = onCropped
        self.onChooseDifferentPhoto = onChooseDifferentPhoto
    }

    // MARK: Internal

    let onCropped: (Data) -> Void
    let onChooseDifferentPhoto: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            cropSurface
                .padding(.top, 24)

            aspectRatioControls

            transformControls

            backgroundRemovalControl

            accessibleControls

            VStack(spacing: 12) {
                Button("Use This Photo") { commitCrop() }
                    .buttonStyle(.borderedProminent)
                Button("Choose a Different Photo", role: .cancel) { onChooseDifferentPhoto() }
            }

            Spacer()
        }
        .padding(.horizontal)
    }

    // MARK: Private

    /// `Square` produces a 512x512 sticker; `original` follows the (possibly rotated) source
    /// photo's own proportions, producing a non-square sticker with its longer side at 512 - both
    /// map directly to Telegram's own crop tool's Square/Original aspect-ratio presets.
    private enum AspectRatioOption: Equatable {
        case square
        case original
    }

    @State private var currentImage: CGImage
    @State private var aspectRatioOption = AspectRatioOption.square
    @State private var zoom: CGFloat = 1
    @State private var offset = CGSize.zero
    @State private var gestureStartZoom: CGFloat = 1
    @State private var gestureStartOffset = CGSize.zero
    @State private var isRemovingBackground = false
    @State private var backgroundRemovalErrorMessage: String?

    private let sourceImage: CGImage

    private let maxPreviewDimension: CGFloat = 300
    private let maxZoom: CGFloat = 4
    private let zoomStep: CGFloat = 0.25
    private let panStep: CGFloat = 0.2

    private var imagePixelSize: CGSize {
        CGSize(width: currentImage.width, height: currentImage.height)
    }

    private var aspectRatio: CGFloat {
        switch aspectRatioOption {
        case .square: 1
        case .original: imagePixelSize.width / imagePixelSize.height
        }
    }

    /// The crop window's on-screen size - its longer side is fixed at `maxPreviewDimension`,
    /// matching how the rendered sticker's longer side is always exactly 512.
    private var previewSize: CGSize {
        aspectRatio >= 1
            ? CGSize(width: maxPreviewDimension, height: maxPreviewDimension / aspectRatio)
            : CGSize(width: maxPreviewDimension * aspectRatio, height: maxPreviewDimension)
    }

    private var cropRect: CGRect {
        TelegramStickerCropRendering.normalizedCropRect(
            imageSize: imagePixelSize,
            aspectRatio: aspectRatio,
            zoom: zoom,
            offset: offset,
        )
    }

    private var cropSummary: String {
        let zoomPercent = Int((zoom * 100).rounded())
        let horizontal = offset.width < -0.05 ? "left" : (offset.width > 0.05 ? "right" : nil)
        let vertical = offset.height < -0.05 ? "up" : (offset.height > 0.05 ? "down" : nil)
        let pan = [vertical, horizontal].compactMap(\.self).joined(separator: " and ")
        return pan.isEmpty
            ? "Zoom \(zoomPercent) percent, centered"
            : "Zoom \(zoomPercent) percent, panned \(pan)"
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                zoom = clampedZoom(gestureStartZoom * value)
            }
            .onEnded { _ in
                gestureStartZoom = zoom
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                let size = previewSize
                offset = CGSize(
                    width: clampedOffset(gestureStartOffset.width - value.translation.width / (size.width / 2)),
                    height: clampedOffset(gestureStartOffset.height - value.translation.height / (size.height / 2)),
                )
            }
            .onEnded { _ in
                gestureStartOffset = offset
            }
    }

    private var backgroundRemovalErrorIsPresented: Binding<Bool> {
        Binding(
            get: { backgroundRemovalErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    backgroundRemovalErrorMessage = nil
                }
            },
        )
    }

    private var cropSurface: some View {
        let rect = cropRect
        let size = previewSize
        let displayWidth = rect.width > 0 ? size.width / rect.width : size.width
        let imageAspectRatio = imagePixelSize.width > 0 ? imagePixelSize.height / imagePixelSize.width : 1
        let displayHeight = displayWidth * imageAspectRatio

        return Image(currentImage, scale: 1, label: Text("Photo"))
            .resizable()
            .frame(width: displayWidth, height: displayHeight)
            .offset(x: -rect.minX * displayWidth, y: -rect.minY * displayHeight)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .clipped()
            .overlay(Rectangle().stroke(.white, lineWidth: 2))
            .contentShape(Rectangle())
            .gesture(SimultaneousGesture(magnificationGesture, dragGesture))
            .accessibilityElement()
            .accessibilityLabel("Sticker crop preview")
            .accessibilityValue(cropSummary)
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: adjustZoom(by: zoomStep)
                case .decrement: adjustZoom(by: -zoomStep)
                default: break
                }
            }
    }

    private var aspectRatioControls: some View {
        Picker("Aspect Ratio", selection: $aspectRatioOption) {
            Text("Square").tag(AspectRatioOption.square)
            Text("Original").tag(AspectRatioOption.original)
        }
        .pickerStyle(.segmented)
        .onChange(of: aspectRatioOption) {
            zoom = 1
            offset = .zero
            gestureStartZoom = 1
            gestureStartOffset = .zero
        }
    }

    private var transformControls: some View {
        HStack {
            Button("Rotate") { rotate() }
            Spacer()
            Button("Mirror") { mirror() }
            Spacer()
            Button("Reset") { reset() }
        }
    }

    private var backgroundRemovalControl: some View {
        HStack {
            if isRemovingBackground {
                ProgressView()
            } else {
                Button("Remove Background") { removeBackground() }
            }
        }
        .alert(
            "Couldn't Remove Background",
            isPresented: backgroundRemovalErrorIsPresented,
        ) {
            Button("OK") {}
        } message: {
            Text(backgroundRemovalErrorMessage ?? "")
        }
    }

    private var accessibleControls: some View {
        VStack(spacing: 12) {
            HStack {
                Button("Zoom Out") { adjustZoom(by: -zoomStep) }
                Spacer()
                Button("Zoom In") { adjustZoom(by: zoomStep) }
            }
            HStack {
                Button("Move Left") { adjustOffset(dx: -panStep, dy: 0) }
                Spacer()
                Button("Move Right") { adjustOffset(dx: panStep, dy: 0) }
            }
            HStack {
                Button("Move Up") { adjustOffset(dx: 0, dy: -panStep) }
                Spacer()
                Button("Move Down") { adjustOffset(dx: 0, dy: panStep) }
            }
        }
    }

    /// `@concurrent` (Swift 6.2) offloads this off the caller's actor while staying a structured
    /// child of `removeBackground()`'s `Task` - unlike `Task.detached`, cancelling that `Task`
    /// actually propagates here instead of only discarding the result after the work finishes.
    @concurrent private static func removingBackgroundConcurrently(from image: CGImage) async throws -> CGImage {
        try TelegramStickerBackgroundRemoval.removingBackground(from: image)
    }

    private func adjustZoom(by delta: CGFloat) {
        zoom = clampedZoom(zoom + delta)
        gestureStartZoom = zoom
    }

    private func adjustOffset(dx: CGFloat, dy: CGFloat) {
        offset = CGSize(width: clampedOffset(offset.width + dx), height: clampedOffset(offset.height + dy))
        gestureStartOffset = offset
    }

    private func clampedZoom(_ value: CGFloat) -> CGFloat {
        min(max(value, 1), maxZoom)
    }

    private func clampedOffset(_ value: CGFloat) -> CGFloat {
        min(max(value, -1), 1)
    }

    private func removeBackground() {
        let imageToProcess = currentImage
        isRemovingBackground = true
        Task {
            defer { isRemovingBackground = false }
            do {
                currentImage = try await Self.removingBackgroundConcurrently(from: imageToProcess)
            } catch {
                backgroundRemovalErrorMessage = error.localizedDescription
            }
        }
    }

    private func rotate() {
        guard let rotated = TelegramStickerCropRendering.rotated90DegreesCounterclockwise(currentImage) else { return }
        currentImage = rotated
    }

    private func mirror() {
        guard let mirrored = TelegramStickerCropRendering.mirroredHorizontally(currentImage) else { return }
        currentImage = mirrored
    }

    private func reset() {
        currentImage = sourceImage
        aspectRatioOption = .square
        zoom = 1
        offset = .zero
        gestureStartZoom = 1
        gestureStartOffset = .zero
    }

    private func commitCrop() {
        guard let cropped = TelegramStickerCropRendering.renderedCropImage(
            source: currentImage,
            normalizedCropRect: cropRect,
        ),
            let pngData = TelegramStickerCropRendering.pngData(from: cropped)
        else { return }
        onCropped(pngData)
    }
}
