// TelegramStickerSetPickerRow.swift

import SwiftUI
import TDLibKit

// MARK: - TelegramStickerSetPickerRow

struct TelegramStickerSetPickerRow: View {
    let stickerSet: StickerSetInfo
    let isInstalling: Bool
    let showsInstallButton: Bool
    let onOpen: () -> Void
    let onInstall: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onOpen) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(stickerSet.title)
                        Text("\(stickerSet.size) stickers")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            if showsInstallButton {
                if isInstalling {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Installing \(stickerSet.title)")
                } else {
                    Button("Install", systemImage: "plus", action: onInstall)
                        .buttonStyle(.bordered)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }
}
