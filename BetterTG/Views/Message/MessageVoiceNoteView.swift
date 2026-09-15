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
        AsyncTdFile(id: voiceNote.voice.id, autoDownloads: autoDownloadsVoiceNote) { voice in
            voiceNoteView(isDownloading: false, file: voice)
                .onAppear {
                    voiceLocalPath = voice.local.path
                    onLocalPathResolved(voice.local.path)
                }
        } placeholder: { file in
            voiceNoteView(isDownloading: file?.local.isDownloadingActive == true, file: file)
        }
        .padding(4)
        // MessageView exposes one stable accessibility element whose default
        // activation toggles playback, matching Telegram's message behavior.
        .accessibilityHidden(true)
    }
    
    func voiceNoteView(isDownloading: Bool, file: File?) -> some View {
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
                    // `onPlaybackToggle` (`ChatVM.toggleVoiceMessage`) downloads on demand when
                    // there's no local path yet, same as VoiceOver's row-level activation already
                    // does - a not-yet-prefetched voice note still plays on an explicit tap.
                    TelegramAudioPlayer.shared.stop()
                    onPlaybackToggle()
                } label: {
                    Circle()
                        .fill(.white)
                        .frame(width: 34)
                        .overlay {
                            ZStack {
                                Image(systemName: playbackImageName)
                                    .font(.system(size: 18))
                                    .foregroundStyle(Color.gray6)
                                    .opacity(isDownloading ? 0 : 1)
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .tint(Color.gray6)
                                    .opacity(isDownloading ? 1 : 0)
                            }
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

                if isCurrentVoiceActive {
                    Button {
                        media.cyclePlaybackRate()
                    } label: {
                        Text(TelegramVoicePlaybackRateSettings.title(for: media.playbackRate))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                    }
                }
            }
            .font(.system(size: 24))

            ZStack {
                Text(TelegramFileTransferProgress.downloadLabel(file: file) ?? "")
                    .opacity(isDownloading ? 1 : 0)
                HStack(spacing: 0) {
                    Text(media.savedMediaPath == voiceLocalPath ? formattedDuration(from: media.currentTime) : "0:00")
                    Text(" / ")
                    Text(formattedDuration(from: voiceNote.duration))
                }
                .opacity(isDownloading ? 0 : 1)
            }
            .font(.system(.caption, design: .rounded))
            .foregroundStyle(.white.opacity(0.5))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 15)
    }
    
    func formattedDuration(from duration: some BinaryInteger) -> String {
        Duration(secondsComponent: Int64(duration), attosecondsComponent: 0)
            .formatted(.time(pattern: .minuteSecond))
    }

    // MARK: Private

    @State private var voiceLocalPath: String?

    /// Just a background-prefetch gate so playback is instant once tapped when allowed - actual
    /// playback (`onPlaybackToggle`) always downloads on demand regardless of this.
    private var autoDownloadsVoiceNote: Bool {
        let settings = TelegramAutoDownloadStore.effectiveSettings(for: TelegramNetworkTypeMonitor.shared.current)
        return TelegramAutoDownloadPolicy.shouldAutoDownload(
            kind: .voiceNote,
            fileSize: max(voiceNote.voice.size, voiceNote.voice.expectedSize),
            settings: settings,
        )
    }

    private var isCurrentVoiceActive: Bool { media.savedMediaPath == voiceLocalPath && media.isPlaying }

    private var playbackImageName: String {
        if isCurrentVoiceActive {
            "pause.fill"
        } else if isViewOnce {
            "1.circle.fill"
        } else {
            "play.fill"
        }
    }
}
