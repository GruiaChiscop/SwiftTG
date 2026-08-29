// ChatInfoHeaderActionsView.swift

import SwiftUI

// MARK: - ChatInfoHeaderActionsView

struct ChatInfoHeaderActionsView: View {
    let canStartAudioCall: Bool
    let canStartVideoCall: Bool
    let startAudioCall: () -> Void
    let startVideoCall: () -> Void
    let search: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if canStartAudioCall {
                Button(action: startAudioCall) {
                    VStack(spacing: 4) {
                        Image(systemName: "phone.fill")
                        Text("Call")
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
            }

            if canStartVideoCall {
                Button(action: startVideoCall) {
                    VStack(spacing: 4) {
                        Image(systemName: "video.fill")
                        Text("Video")
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
            }

            Button(action: search) {
                VStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                    Text("Search")
                        .font(.caption)
                }
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
        }
    }
}
