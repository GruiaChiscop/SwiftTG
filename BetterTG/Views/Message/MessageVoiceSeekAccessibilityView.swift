// MessageVoiceSeekAccessibilityView.swift

import SwiftUI

/// A stable, native slider for the waveform's accessibility representation.
struct MessageVoiceSeekAccessibilityView: View {
    // MARK: Internal

    let localPath: String?
    let duration: Int

    var body: some View {
        Slider(value: seekPosition, in: 0...Double(max(1, duration))) {
            Text("Voice Message Position")
        }
        .accessibilityValue(
            "\(telegramSpokenDuration(Int(position))) of \(telegramSpokenDuration(duration))",
        )
        .accessibilityFocused($isFocused)
        .accessibilityAdjustableAction { direction in
            guard isCurrentVoiceActive else { return }
            let forward: Bool
            switch direction {
            case .increment: forward = true
            case .decrement: forward = false
            @unknown default: return
            }
            // Adjust the value VoiceOver last announced, not the playback clock that
            // has advanced while the user was listening to that announcement.
            media.seek(to: TelegramVoiceSkipSettings.nextPosition(
                from: position,
                duration: duration,
                forward: forward,
            ))
            synchronizePosition()
        }
        .onAppear(perform: synchronizePosition)
        .onChange(of: isFocused) { _, _ in synchronizePosition() }
        .onChange(of: media.currentTime) { _, _ in
            // Keep VoiceOver's focused value stable between explicit adjustments.
            // Playback ticks should not continually update the element being spoken.
            guard !isFocused else { return }
            synchronizePosition()
        }
    }

    // MARK: Private

    @AccessibilityFocusState private var isFocused: Bool
    @State private var media = Media.shared
    @State private var position = 0.0

    private var isCurrentVoiceActive: Bool {
        guard let localPath, !localPath.isEmpty else { return false }
        return media.savedMediaPath == localPath
    }

    /// A write is a user seek; reading/synchronizing progress must never seek the player.
    private var seekPosition: Binding<Double> {
        Binding(
            get: { position },
            set: { seconds in
                guard isCurrentVoiceActive else { return }
                media.seek(to: seconds)
                synchronizePosition()
            },
        )
    }

    private func synchronizePosition() {
        position = isCurrentVoiceActive ? min(Double(duration), Double(media.currentTime)) : 0
    }
}
