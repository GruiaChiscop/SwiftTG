// MessageVoiceNoteView.swift

import SwiftUI
import TDLibKit

struct MessageVoiceNoteView: View {
    // MARK: Internal

    let voiceNote: VoiceNote
    let isViewOnce: Bool
    var onPlaybackToggle: () -> Void = {}
    var onLocalPathResolved: (String) -> Void = { _ in }

    @State var media = Media.shared

    var body: some View {
        AsyncTdFile(id: voiceNote.voice.id) { voice in
            voiceNoteView
                .onAppear {
                    voiceLocalPath = voice.local.path
                    onLocalPathResolved(voice.local.path)
                }
        } placeholder: {
            voiceNoteView
        }
        .padding(4)
        .disabled(voiceLocalPath == nil)
        // MessageView exposes one stable accessibility element whose default
        // activation toggles playback, matching Telegram's message behavior.
        .accessibilityHidden(true)
    }
    
    var voiceNoteView: some View {
        VStack(spacing: 5) {
            HStack(spacing: 10) {
                if !isViewOnce {
                    Button {
                        media.seekBackward()
                    } label: {
                        Image(systemName: "gobackward.5")
                    }
                    .disabled(!isCurrentVoiceActive)
                }

                Button {
                    guard voiceLocalPath != nil else { return }
                    TelegramAudioPlayer.shared.stop()
                    onPlaybackToggle()
                } label: {
                    Circle()
                        .fill(.white)
                        .frame(width: 34)
                        .overlay {
                            Group {
                                if isCurrentVoiceActive {
                                    Image(systemName: "pause.fill")
                                        .transition(.scale)
                                } else {
                                    Image(systemName: isViewOnce ? "1.circle.fill" : "play.fill")
                                        .transition(.scale)
                                }
                            }
                            .font(.system(size: 18))
                            .foregroundStyle(Color.gray6)
                        }
                }
                .accessibilityValue(formattedDuration(from: voiceNote.duration))

                if !isViewOnce {
                    Button {
                        media.seekForward()
                    } label: {
                        Image(systemName: "goforward.5")
                    }
                    .disabled(!isCurrentVoiceActive)
                }
            }
            .font(.system(size: 24))

            HStack(spacing: 0) {
                Text(media.savedMediaPath == voiceLocalPath ? formattedDuration(from: media.currentTime) : "0:00")
                Text(" / ")
                Text(formattedDuration(from: voiceNote.duration))
            }
            .font(.system(.caption, design: .rounded))
            .foregroundStyle(.white.opacity(0.5))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 15)
        .animation(.default, value: isCurrentVoiceActive)
    }
    
    func formattedDuration(from duration: some BinaryInteger) -> String {
        Duration(secondsComponent: Int64(duration), attosecondsComponent: 0)
            .formatted(.time(pattern: .minuteSecond))
    }

    // MARK: Private

    @State private var voiceLocalPath: String?

    private var isCurrentVoiceActive: Bool { media.savedMediaPath == voiceLocalPath && media.isPlaying }
}
