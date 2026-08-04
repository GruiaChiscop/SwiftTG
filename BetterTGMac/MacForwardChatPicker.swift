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
                        Text(chat.displayTitle)
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
        return all.filter { $0.displayTitle.localizedCaseInsensitiveContains(query) }
    }

    private func avatar(for chat: ChatListItemState) -> some View {
        Circle()
            .fill(chat.isSavedMessages
                ? AnyShapeStyle(Color.accentColor.gradient)
                : AnyShapeStyle(Color(telegramAvatarId: chat.chatId)))
                .overlay {
                    if chat.isSavedMessages {
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                    } else {
                        Text(String(chat.title.prefix(1)).uppercased())
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)
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
