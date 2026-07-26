// ForwardChatPickerView.swift

import SwiftUI

struct ForwardChatPickerView: View {
    let message: CustomMessage
    let chatVM: ChatVM

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selectedChatIds = Set<Int64>()
    @State private var isForwarding = false

    var body: some View {
        NavigationStack {
            List(chats) { chat in
                Button {
                    toggle(chat)
                } label: {
                    HStack(spacing: 12) {
                        ProfileImageView(
                            photo: chat.chat.photo?.small,
                            minithumbnail: chat.chat.photo?.minithumbnail,
                            title: chat.chat.title,
                            userId: chat.chat.id,
                            fontSize: 18,
                        )
                        .frame(width: 40, height: 40)

                        Text(chat.chat.title)
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Spacer()

                        Image(systemName: selectedChatIds.contains(chat.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selectedChatIds.contains(chat.id) ? Color.accentColor : .secondary)
                            .accessibilityHidden(true)
                    }
                }
                .disabled(isForwarding)
                .accessibilityLabel(chat.chat.title)
                .accessibilityAddTraits(selectedChatIds.contains(chat.id) ? .isSelected : [])
                .accessibilityHint("Toggles this chat as a forward destination")
            }
            .listStyle(.plain)
            .searchable(text: $query, prompt: "Search chats")
            .navigationTitle("Forward to…")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isForwarding {
                        ProgressView()
                    } else {
                        Button("Forward") { forward() }
                            .disabled(selectedChatIds.isEmpty)
                    }
                }
            }
        }
    }

    private var chats: [CustomChat] {
        let allChats = RootVM.shared.allChats
        guard !query.isEmpty else { return allChats }
        return allChats.filter { $0.chat.title.localizedCaseInsensitiveContains(query) }
    }

    private func toggle(_ chat: CustomChat) {
        if !selectedChatIds.insert(chat.id).inserted {
            selectedChatIds.remove(chat.id)
        }
    }

    private func forward() {
        let destinations = RootVM.shared.allChats.filter { selectedChatIds.contains($0.id) }
        guard !destinations.isEmpty else { return }
        isForwarding = true
        Task.background {
            let success = await chatVM.forwardMessage(message, to: destinations)
            await main {
                dismiss()
                guard success, let onlyDestination = destinations.first, destinations.count == 1 else { return }
                RootVM.shared.navigate(to: .customChat(onlyDestination, messageId: nil))
            }
        }
    }
}
