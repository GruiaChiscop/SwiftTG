// TelegramMediaCrop.swift

import CoreGraphics

// MARK: - TelegramMediaCropAspectRatio

enum TelegramMediaCropAspectRatio: String, CaseIterable, Identifiable, Sendable {
    case original
    case square

    // MARK: Internal

    var id: Self { self }

    var title: String {
        switch self {
        case .original: "Original"
        case .square: "Square"
        }
    }
}

// MARK: - TelegramMediaCrop

struct TelegramMediaCrop: Equatable, Sendable {
    var aspectRatio = TelegramMediaCropAspectRatio.original
    var zoom = 1.0
    var horizontalOffset = 0.0
    var verticalOffset = 0.0
    var quarterTurnsCounterclockwise = 0
    var rotationDegrees = 0.0
    var isMirrored = false

    var isIdentity: Bool {
        self == TelegramMediaCrop()
    }

    var normalizedQuarterTurns: Int {
        ((quarterTurnsCounterclockwise % 4) + 4) % 4
    }

    func rotatedCanvasSize(for canvasSize: CGSize) -> CGSize {
        normalizedQuarterTurns.isMultiple(of: 2)
            ? canvasSize
            : CGSize(width: canvasSize.height, height: canvasSize.width)
    }
}
