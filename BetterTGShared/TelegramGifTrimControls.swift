// TelegramGifTrimControls.swift

import SwiftUI

struct TelegramGifTrimControls: View {
    @Binding var startTime: Double
    @Binding var endTime: Double

    let duration: Double
    let minimumDuration: Double

    var body: some View {
        VStack(alignment: .leading) {
            LabeledContent("Start") {
                Text(startTime, format: .number.precision(.fractionLength(1)))
                    .monospacedDigit()
            }
            Slider(
                value: $startTime,
                in: 0...max(0, endTime - minimumDuration),
                step: 0.1,
            )

            LabeledContent("End") {
                Text(endTime, format: .number.precision(.fractionLength(1)))
                    .monospacedDigit()
            }
            Slider(
                value: $endTime,
                in: min(duration, startTime + minimumDuration)...duration,
                step: 0.1,
            )
        }
    }
}
