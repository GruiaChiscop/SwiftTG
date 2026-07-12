// MessageContentView.swift

import SwiftUI
import TDLibKit

struct MessageContentView: View {
    let customMessage: CustomMessage
    let onPhotoTap: (Message?) -> Void
    var onVoiceNoteLocalPathResolved: (String) -> Void = { _ in }

    var body: some View {
        ZStack {
            if customMessage.album.isEmpty {
                switch customMessage.message.content {
                case .messagePhoto(let messagePhoto):
                    makeMessagePhoto(from: messagePhoto)
                        .scaledToFit()
                case .messageVoiceNote(let messageVoiceNote):
                    MessageVoiceNoteView(
                        voiceNote: messageVoiceNote.voiceNote,
                        onLocalPathResolved: onVoiceNoteLocalPathResolved,
                    )
                default:
                    EmptyView()
                }
            } else {
                MediaAlbum {
                    ForEach(customMessage.album) { albumMessage in
                        if case .messagePhoto(let messagePhoto) = albumMessage.content {
                            makeMessagePhoto(from: messagePhoto, albumMessage: albumMessage)
                        }
                    }
                }
                .clipShape(.rect(cornerRadius: 13))
            }
        }
        .padding(1)
    }

    func makeMessagePhoto(from messagePhoto: MessagePhoto, albumMessage: Message? = nil) -> some View {
        TdImage(photo: messagePhoto.photo, size: .yBox, contentMode: .fill)
            .onTapGesture { onPhotoTap(albumMessage) }
            .accessibilityLabel(messagePhoto.caption.text.isEmpty ? "Photo" : "Photo: \(messagePhoto.caption.text)")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onPhotoTap(albumMessage) }
    }
}
