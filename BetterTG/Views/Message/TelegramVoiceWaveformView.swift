// TelegramVoiceWaveformView.swift

import SwiftUI

/// A draggable waveform seek bar for a voice message, matching Telegram-iOS's own visual style
/// (2pt bars, 2pt gaps, resampled to fit the available width - `AudioWaveformComponent.swift`)
/// but WhatsApp's simpler absolute tap/drag-to-position interaction rather than Telegram-iOS's
/// relative-delta-plus-vertical-fine-scrub gesture.
///
/// Purely a visual/touch affordance - `.accessibilityHidden(true)`, since VoiceOver users already
/// get seeking through the Skip Forward/Skip Backward actions (`MessageView`), and exposing this
/// too as an `.accessibilityAdjustableAction` would just be a second, redundant way to do the same
/// thing.
struct TelegramVoiceWaveformView: View {
    let samples: [UInt8]
    /// 0...1. Ignored while the user is actively dragging - the drag position takes over the
    /// visual played/unplayed split until released.
    let progress: Double
    /// Called once, on release, with the final 0...1 fraction to seek to.
    let onSeek: (Double) -> Void

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                draw(in: &context, size: size)
            }
            .contentShape(Rectangle())
            .gesture(
                // A non-zero minimum distance matters here specifically because this sits inside
                // a scrollable message list - `minimumDistance: 0` would claim a touch the instant
                // it lands, even one that turns out to be a vertical scroll starting on top of the
                // waveform, starving the List's own pan gesture of a fair chance to win it. That
                // same threshold means a plain tap (no movement) never crosses it, so it's paired
                // with a separate tap gesture below for "tap directly on a position to jump there".
                DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        dragProgress = fraction(for: value.location.x, width: geometry.size.width)
                    }
                    .onEnded { value in
                        let final = fraction(for: value.location.x, width: geometry.size.width)
                        dragProgress = nil
                        onSeek(final)
                    },
            )
            .simultaneousGesture(
                SpatialTapGesture()
                    .onEnded { value in
                        onSeek(fraction(for: value.location.x, width: geometry.size.width))
                    },
            )
        }
        .frame(height: 18)
        .accessibilityHidden(true)
    }

    // MARK: Private

    @State private var dragProgress: Double?

    private func fraction(for x: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return Double(min(max(x / width, 0), 1))
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let sampleWidth: CGFloat = 2
        let gap: CGFloat = 2
        let barCount = max(1, Int(size.width / (sampleWidth + gap)))
        let binned = Self.resample(samples, to: barCount)
        guard !binned.isEmpty else { return }
        let displayedProgress = dragProgress ?? progress
        for (index, amplitude) in binned.enumerated() {
            let x = CGFloat(index) * (sampleWidth + gap)
            let heightFraction = CGFloat(amplitude) / 31
            let barHeight = max(2, heightFraction * size.height)
            let rect = CGRect(x: x, y: (size.height - barHeight) / 2, width: sampleWidth, height: barHeight)
            let isPlayed = Double(index) / Double(binned.count) <= displayedProgress
            context.fill(
                Path(roundedRect: rect, cornerRadius: sampleWidth / 2),
                with: .color(.white.opacity(isPlayed ? 1 : 0.4)),
            )
        }
    }

    /// Bins samples down to `count` bars (Telegram-iOS's own approach for a waveform with more
    /// samples than fit the available width) by taking the loudest sample in each bin, so quiet
    /// gaps between loud moments don't get smoothed away.
    private static func resample(_ samples: [UInt8], to count: Int) -> [UInt8] {
        guard !samples.isEmpty, count > 0 else { return [] }
        guard samples.count > count else { return samples }
        var result = [UInt8]()
        result.reserveCapacity(count)
        for bin in 0..<count {
            let start = bin * samples.count / count
            let end = max(start + 1, (bin + 1) * samples.count / count)
            result.append(samples[start..<end].max() ?? 0)
        }
        return result
    }
}
