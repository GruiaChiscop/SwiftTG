// TelegramVideoNoteEditing.swift

@preconcurrency import AVFoundation
import Foundation
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - TelegramVideoNoteThumbnail

struct TelegramVideoNoteThumbnail: Sendable {
    let url: URL
    let width: Int
    let height: Int
}

// MARK: - TelegramVideoNoteRecordedFileReusePolicy

enum TelegramVideoNoteRecordedFileReusePolicy {
    static func canReuse(
        segmentCount: Int,
        trimRange: Range<Double>,
        duration: Double,
    ) -> Bool {
        let tolerance = 0.05
        return segmentCount == 1
            && abs(trimRange.lowerBound) <= tolerance
            && abs(trimRange.upperBound - duration) <= tolerance
    }
}

// MARK: - TelegramVideoNoteEditing

enum TelegramVideoNoteEditing {
    // MARK: Internal

    static let minimumTrimDuration = 1.0

    static func isSendableDuration(_ duration: Double) -> Bool {
        duration.isFinite && duration >= minimumTrimDuration
    }

    static func normalizedTrimRange(
        start: Double,
        end: Double,
        duration: Double,
    ) -> Range<Double> {
        let safeDuration = max(0, duration.isFinite ? duration : 0)
        guard safeDuration > 0 else { return 0..<0 }
        let minimumDuration = min(minimumTrimDuration, safeDuration)
        let lowerBound = min(max(start.isFinite ? start : 0, 0), safeDuration - minimumDuration)
        let proposedEnd = end.isFinite && end > 0 ? end : safeDuration
        let upperBound = min(
            max(proposedEnd, lowerBound + minimumDuration),
            safeDuration,
        )
        return lowerBound..<upperBound
    }

    static func combinedAsset(sourceURLs: [URL]) async throws -> AVAsset {
        guard !sourceURLs.isEmpty else { throw EditingError.noVideo }
        if sourceURLs.count == 1, let sourceURL = sourceURLs.first {
            return AVURLAsset(url: sourceURL)
        }

        let composition = AVMutableComposition()
        var insertionTime = CMTime.zero
        for sourceURL in sourceURLs {
            let segment = AVURLAsset(url: sourceURL)
            let segmentDuration = try await segment.load(.duration)
            guard segmentDuration.isValid, segmentDuration.isNumeric, segmentDuration > .zero else {
                continue
            }
            try await composition.insertTimeRange(
                CMTimeRange(start: .zero, duration: segmentDuration),
                of: segment,
                at: insertionTime,
            )
            insertionTime = insertionTime + segmentDuration
        }
        guard insertionTime > .zero else { throw EditingError.noVideo }
        return composition
    }

    static func trimmedAsset(
        sourceURLs: [URL],
        trimRange: Range<Double>,
    ) async throws -> AVAsset {
        let asset = try await combinedAsset(sourceURLs: sourceURLs)
        let duration = try await asset.load(.duration)
        guard duration.isValid, duration.isNumeric, duration > .zero else {
            throw EditingError.noVideo
        }
        let effectiveRange = normalizedTrimRange(
            start: trimRange.lowerBound,
            end: trimRange.upperBound,
            duration: duration.seconds,
        )
        let composition = AVMutableComposition()
        try await composition.insertTimeRange(
            CMTimeRange(
                start: CMTime(seconds: effectiveRange.lowerBound, preferredTimescale: 600),
                duration: CMTime(
                    seconds: effectiveRange.upperBound - effectiveRange.lowerBound,
                    preferredTimescale: 600,
                ),
            ),
            of: asset,
            at: .zero,
        )
        return composition
    }

    static func generateThumbnail(
        videoURL: URL,
        outputURL: URL,
    ) async throws -> TelegramVideoNoteThumbnail {
        let asset = AVURLAsset(url: videoURL)
        let duration = try await asset.load(.duration)
        guard duration.isValid, duration.isNumeric, duration > .zero else {
            throw EditingError.noVideo
        }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 320, height: 320)
        let time = CMTime(
            seconds: min(0.1, duration.seconds / 2),
            preferredTimescale: 600,
        )
        let image = try await generator.image(at: time).image
        guard let jpegData = jpegData(for: image) else {
            throw EditingError.thumbnailEncodingFailed
        }
        try jpegData.write(to: outputURL, options: .atomic)
        return TelegramVideoNoteThumbnail(
            url: outputURL,
            width: image.width,
            height: image.height,
        )
    }

    // MARK: Private

    private enum EditingError: Error {
        case noVideo
        case thumbnailEncodingFailed
    }

    private static func jpegData(for image: CGImage) -> Data? {
        let compressionQualities: [CGFloat] = [0.72, 0.55, 0.4, 0.25]
        for quality in compressionQualities {
            #if os(iOS)
            let data = UIImage(cgImage: image).jpegData(compressionQuality: quality)
            #elseif os(macOS)
            let data = NSBitmapImageRep(cgImage: image).representation(
                using: .jpeg,
                properties: [.compressionFactor: quality],
            )
            #endif
            if let data, data.count < 200_000 {
                return data
            }
        }
        return nil
    }
}
