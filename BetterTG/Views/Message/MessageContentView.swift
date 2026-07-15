// MessageContentView.swift

import SwiftUI
import TDLibKit

struct MessageContentView: View {
    let customMessage: CustomMessage
    let onMediaTap: (Message?) -> Void
    var onVoiceNoteLocalPathResolved: (String) -> Void = { _ in }

    var body: some View {
        ZStack {
            if customMessage.album.isEmpty {
                switch customMessage.message.content {
                case .messageDocument(let messageDocument):
                    MessageDocumentView(document: messageDocument.document)
                case .messagePhoto(let messagePhoto):
                    makeMessagePhoto(from: messagePhoto)
                        .scaledToFit()
                case .messageVideo(let messageVideo):
                    makeMessageVideo(from: messageVideo)
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
                        } else if case .messageVideo(let messageVideo) = albumMessage.content {
                            makeMessageVideo(from: messageVideo, albumMessage: albumMessage)
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
            .onTapGesture { onMediaTap(albumMessage) }
            .accessibilityLabel(messagePhoto.caption.text.isEmpty ? "Photo" : "Photo: \(messagePhoto.caption.text)")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onMediaTap(albumMessage) }
    }

    func makeMessageVideo(from messageVideo: MessageVideo, albumMessage: Message? = nil) -> some View {
        ZStack {
            TdVideoThumbnail(messageVideo: messageVideo, contentMode: .fill)

            Image(systemName: "play.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.white)
                .shadow(radius: 3)

            Text(telegramClockDuration(messageVideo.video.duration))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(.black.opacity(0.7), in: Capsule())
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(8)
        }
        .frame(minWidth: 220, minHeight: 150)
        .clipShape(.rect(cornerRadius: 13))
        .contentShape(.rect)
        .onTapGesture { onMediaTap(albumMessage) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Video, duration \(telegramClockDuration(messageVideo.video.duration))")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onMediaTap(albumMessage) }
    }
}
