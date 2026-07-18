// ChatInfoView.swift

import SwiftUI

// MARK: - ChatInfoView

struct ChatInfoView: View {
    @Environment(ChatVM.self) private var chatVM
    @Environment(\.dismiss) private var dismiss

    let onSharedMedia: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    identity
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                Section {
                    Button {
                        onSharedMedia()
                    } label: {
                        Label("Shared Media", systemImage: "photo.on.rectangle")
                    }

                    if chat.chat.canBeDeletedOnlyForSelf || chat.chat.canBeDeletedForAllUsers {
                        Button(role: .destructive) {
                            dismiss()
                            RootVM.shared.requestClearHistory(chatVM.customChat)
                        } label: {
                            Label("Clear History", systemImage: "eraser")
                        }
                    }
                }
            }
            .navigationTitle("Chat Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var chat: CustomChat { chatVM.customChat }

    private var status: String {
        !chatVM.actionStatus.isEmpty ? chatVM.actionStatus : chatVM.onlineStatus
    }

    private var identity: some View {
        VStack(spacing: 12) {
            ProfileImageView(
                photo: chat.chat.photo?.big,
                minithumbnail: chat.chat.photo?.minithumbnail,
                title: chat.chat.title,
                userId: chat.chat.id,
                fontSize: 36,
            )
            .frame(width: 96, height: 96)

            Text(chat.chat.title)
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            if !status.isEmpty {
                Text(status)
                    .font(.subheadline)
                    .foregroundStyle(status == "online" ? .blue : .secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
