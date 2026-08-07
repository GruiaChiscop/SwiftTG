// TelegramMutePresetPopover.swift

import SwiftUI

/// Content for the mute-duration popover shown from chat info on both platforms - a plain,
/// content-sized menu rather than a `List`, since a List tends to want to expand and scroll even
/// for a handful of rows, working against what a small popover should look like.
struct TelegramMutePresetPopoverContent: View {
    let onSelect: (Int) -> Void

    var body: some View {
        let presets = Array(TelegramMutePreset.allCases.enumerated())
        VStack(alignment: .leading, spacing: 0) {
            ForEach(presets, id: \.element.id) { index, preset in
                Button {
                    onSelect(preset.duration)
                } label: {
                    Text(preset.title)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if index < presets.count - 1 {
                    Divider()
                }
            }
        }
        .frame(minWidth: 200)
    }
}
