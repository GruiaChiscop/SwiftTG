// VideoChatRtmpView.swift

import SwiftUI
import TDLibKit

// MARK: - VideoChatRtmpView

struct VideoChatRtmpView: View {
    // MARK: Internal

    let chatId: Int64
    let service: any TelegramService
    let createsStream: Bool
    let onCreated: ((GroupCall) -> Void)?

    var body: some View {
        Form {
            if isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView("Preparing stream…")
                        Spacer()
                    }
                }
            } else if let credentials {
                Section("Streaming Software") {
                    LabeledContent("Server URL", value: credentials.url)
                        .textSelection(.enabled)
                    LabeledContent("Stream Key", value: credentials.streamKey)
                        .textSelection(.enabled)
                }
                Section {
                    ShareLink(item: credentials.url) {
                        Label("Share Server URL", systemImage: "square.and.arrow.up")
                    }
                    ShareLink(item: credentials.streamKey) {
                        Label("Share Stream Key", systemImage: "key")
                    }
                    Button("Reset Stream Key", systemImage: "arrow.triangle.2.circlepath", role: .destructive) {
                        Task { await replaceCredentials() }
                    }
                }
            }
        }
        .navigationTitle("Stream with…")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .task { await load() }
        .alert("Stream Error", isPresented: errorIsPresented) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @State private var credentials: RtmpUrl?
    @State private var errorMessage: String?
    @State private var isLoading = true

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: {
                if !$0 {
                    errorMessage = nil
                }
            },
        )
    }

    @MainActor private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            if createsStream {
                let created = try await service.createVideoChat(
                    chatId: chatId,
                    isRtmpStream: true,
                    startDate: 0,
                    title: "",
                )
                let call = try await service.getGroupCall(groupCallId: created.id)
                onCreated?(call)
            }
            credentials = try await service.getVideoChatRtmpUrl(chatId: chatId)
        } catch {
            errorMessage = telegramErrorDescription(error)
        }
    }

    @MainActor private func replaceCredentials() async {
        do {
            credentials = try await service.replaceVideoChatRtmpUrl(chatId: chatId)
        } catch {
            errorMessage = telegramErrorDescription(error)
        }
    }
}
