// ConferenceVideoTileView.swift

import SwiftUI
@preconcurrency import TDLibKit
import UIKit

// MARK: - ConferenceVideoTileView

struct ConferenceVideoTileView: View {
    // MARK: Lifecycle

    init(
        video: ConferenceVideoPresentation,
        requestVideoView: @escaping (String, @escaping @MainActor (UIView?) -> Void) -> Void,
    ) {
        self.video = video
        self.requestVideoView = requestVideoView
    }

    // MARK: Internal

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let videoView {
                CallVideoSurfaceView(videoView: videoView)
                    .id(ObjectIdentifier(videoView))
                    .accessibilityHidden(true)
            } else {
                Color.black
                ProfileImageView(
                    photo: profilePhoto,
                    minithumbnail: profileMinithumbnail,
                    title: displayTitle,
                    userId: avatarId,
                )
                .frame(width: 76, height: 76)
                .accessibilityHidden(true)
            }

            LinearGradient(
                colors: [.clear, .black.opacity(0.75)],
                startPoint: .center,
                endPoint: .bottom,
            )
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(displayTitle)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                if video.isScreenSharing {
                    Label("Screen", systemImage: "rectangle.on.rectangle")
                        .font(.footnote)
                } else if video.isPaused {
                    Label("Paused", systemImage: "video.slash.fill")
                        .font(.footnote)
                }
            }
            .padding(10)
        }
        .clipShape(.rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.2), lineWidth: 1)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
        .task(id: profileIdentity) {
            await loadProfile()
        }
        .onAppear(perform: loadVideoView)
        .onDisappear(perform: discardVideoView)
    }

    // MARK: Private

    @State private var chat: Chat?
    @State private var user: User?
    @State private var videoView: UIView?
    @State private var requestGeneration = UUID()

    private let video: ConferenceVideoPresentation
    private let requestVideoView: (String, @escaping @MainActor (UIView?) -> Void) -> Void

    private var userId: Int64? { video.userId }
    private var chatId: Int64? { video.chatId }
    private var profileIdentity: String { video.participantId }

    private var displayTitle: String {
        if let title = video.title {
            return title
        } else if let user {
            return telegramUserDisplayName(user)
        } else if let chat {
            return chat.title
        }
        return "Participant"
    }

    private var avatarId: Int64 { userId ?? chatId ?? 0 }
    private var profilePhoto: File? { user?.profilePhoto?.small ?? chat?.photo?.small }
    private var profileMinithumbnail: Minithumbnail? {
        user?.profilePhoto?.minithumbnail ?? chat?.photo?.minithumbnail
    }

    private var accessibilityDescription: String {
        let source = video.isScreenSharing ? "screen sharing" : "camera"
        return video.isPaused ? "\(displayTitle), \(source), paused" : "\(displayTitle), \(source)"
    }

    private func loadVideoView() {
        let generation = UUID()
        requestGeneration = generation
        videoView = nil
        requestVideoView(video.endpointId) { view in
            guard requestGeneration == generation else { return }
            videoView = view
        }
    }

    private func discardVideoView() {
        requestGeneration = UUID()
        videoView = nil
    }

    @MainActor private func loadProfile() async {
        user = nil
        chat = nil
        guard video.title == nil else { return }
        let service = TDLib.shared.service
        do {
            if let userId {
                let loadedUser = try await service.getUser(userId: userId)
                try Task.checkCancellation()
                user = loadedUser
            } else if let chatId {
                let loadedChat = try await service.getChat(chatId: chatId)
                try Task.checkCancellation()
                chat = loadedChat
            }
        } catch is CancellationError {
            return
        } catch {
            log("[GroupCall] couldn't load video participant profile \(profileIdentity): \(error)")
        }
    }
}
