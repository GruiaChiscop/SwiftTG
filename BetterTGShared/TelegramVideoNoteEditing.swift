// TelegramVideoNoteEditing.swift

@preconcurrency import AVFoundation
import Foundation

enum TelegramVideoNoteEditing {
    // MARK: Internal

    static let minimumTrimDuration = 0.5

    static func normalizedTrimRange(
        start: Double,
        end: Double,
        duration: Double,
    ) -> Range<Double> {
        let safeDuration = max(0, duration.isFinite ? duration : 0)
        guard safeDuration > 0 else { return 0..<0 }
        let minimumDuration = min(minimumTrimDuration, safeDuration)
        let lowerBound = min(max(start.isFinite ? start : 0, 0), safeDuration - minimumDuration)
        let upperBound = min(
            max(end.isFinite ? end : safeDuration, lowerBound + minimumDuration),
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

    // MARK: Private

    private enum EditingError: Error {
        case noVideo
    }
}
