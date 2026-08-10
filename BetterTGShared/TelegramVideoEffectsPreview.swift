// TelegramVideoEffectsPreview.swift

import AVKit
import SwiftUI

struct TelegramVideoEffectsPreview: View {
    let player: AVPlayer
    let effects: TelegramMediaEffects

    var body: some View {
        VideoPlayer(player: player)
            .disabled(true)
            .brightness(effects.brightness)
            .contrast(effects.contrast)
            .saturation(effects.saturation)
            .blur(radius: effects.blurRadius)
    }
}
