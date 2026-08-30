// MessageContentView.swift

import SwiftUI
import TDLibKit

struct MessageContentView: View {
    let customMessage: CustomMessage
    let audioPlaylist: [Audio]
    let service: any TelegramService
    let onMediaTap: (Message?) -> Void
    var onContactTap: () -> Void = {}
    var onLocationTap: () -> Void = {}
    var onVoiceNoteToggle: () -> Void = {}
    var onVoiceNoteLocalPathResolved: (String) -> Void = { _ in }
    var onDocumentTransferStatusChange: (String?) -> Void = { _ in }
    var documentDownloadIsPaused = false
    var onDocumentDownloadToggle: () -> Void = {}

    var body: some View {
        ZStack {
            if customMessage.album.isEmpty {
                switch customMessage.message.content {
                case .messageDocument(let messageDocument):
                    MessageDocumentView(
                        document: messageDocument.document,
                        service: service,
                        downloadIsPaused: documentDownloadIsPaused,
                        onDownloadToggle: onDocumentDownloadToggle,
                        onTransferStatusChange: onDocumentTransferStatusChange,
                    )
                case .messagePhoto(let messagePhoto):
                    makeMessagePhoto(from: messagePhoto)
                        .scaledToFit()
                case .messageVideo(let messageVideo):
                    makeMessageVideo(from: messageVideo)
                case .messageVideoNote(let messageVideoNote):
                    MessageVideoNoteView(
                        message: customMessage.message,
                        content: messageVideoNote,
                        service: service,
                        player: .shared,
                    )
                case .messageAnimation(let messageAnimation):
                    makeMessageAnimation(from: messageAnimation)
                case .messageVoiceNote(let messageVoiceNote):
                    MessageVoiceNoteView(
                        voiceNote: messageVoiceNote.voiceNote,
                        isViewOnce: customMessage.message.selfDestructType == .messageSelfDestructTypeImmediately,
                        onPlaybackToggle: onVoiceNoteToggle,
                        onLocalPathResolved: onVoiceNoteLocalPathResolved,
                    )
                case .messageAudio(let messageAudio):
                    MessageAudioView(audio: messageAudio.audio, playlist: audioPlaylist)
                case .messageSticker(let messageSticker):
                    TelegramStickerView(
                        content: messageSticker,
                        service: service,
                        playsAnimation: customMessage.message.sendingState == nil,
                    )
                case .messageContact(let messageContact):
                    MessageContactView(content: messageContact, onTap: onContactTap)
                case .messageLiveLocation, .messageLocation, .messageVenue:
                    if let presentation = customMessage.locationPresentation {
                        MessageLocationView(
                            presentation: presentation,
                            messageId: customMessage.id,
                            onTap: onLocationTap,
                            accessibilityActions: { EmptyView() },
                        )
                    }
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

    func makeMessageAnimation(from messageAnimation: MessageAnimation) -> some View {
        ZStack {
            if let thumbnail = messageAnimation.animation.thumbnail {
                AsyncTdImage(id: thumbnail.file.id) { image, _ in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(.black.opacity(0.35))
                }
            } else {
                Rectangle().fill(.black.opacity(0.35))
            }

            Text("GIF")
                .font(.caption.bold())
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
        .onTapGesture { onMediaTap(nil) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            messageAnimation.caption.text.isEmpty ? "GIF" : "GIF: \(messageAnimation.caption.text)",
        )
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onMediaTap(nil) }
    }
}
