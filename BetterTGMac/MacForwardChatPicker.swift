// MacForwardChatPicker.swift

import SwiftUI
import TDLibKit

struct MacForwardChatPicker: View {
    // MARK: Internal

    @Bindable var model: MacSessionModel

    let message: Message

    var body: some View {
        NavigationStack {
            List(chats, id: \.chatId) { chat in
                Button {
                    toggle(chat)
                } label: {
                    HStack(spacing: 10) {
                        avatar(for: chat)
                        Text(chat.title)
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: selectedChatIds.contains(chat.chatId) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selectedChatIds.contains(chat.chatId) ? Color.accentColor : .secondary)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isForwarding)
            }
            .searchable(text: $query, prompt: "Search chats")
            .navigationTitle("Forward to…")
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
        .frame(width: 380, height: 460)
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selectedChatIds = Set<Int64>()
    @State private var isForwarding = false

    private var chats: [ChatListItemState] {
        let all = model.allChatItems
        guard !query.isEmpty else { return all }
        return all.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    private func avatar(for chat: ChatListItemState) -> some View {
        Circle()
            .fill(avatarColor(for: chat.chatId))
            .overlay {
                Text(String(chat.title.prefix(1)).uppercased())
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 32, height: 32)
            .accessibilityHidden(true)
    }

    private func avatarColor(for chatId: Int64) -> Color {
        let palette: [Color] = [.blue, .indigo, .purple, .pink, .orange, .teal]
        return palette[Int(chatId.magnitude % UInt64(palette.count))]
    }

    private func toggle(_ chat: ChatListItemState) {
        if !selectedChatIds.insert(chat.chatId).inserted {
            selectedChatIds.remove(chat.chatId)
        }
    }

    private func forward() {
        let destinationIds = Array(selectedChatIds)
        guard !destinationIds.isEmpty else { return }
        isForwarding = true
        Task {
            let success = await model.forward(message, to: destinationIds)
            dismiss()
            if success, let onlyDestination = destinationIds.first, destinationIds.count == 1 {
                model.activateChat(onlyDestination)
            }
        }
    }
}
