// ForwardChatPickerView.swift

import SwiftUI

struct ForwardChatPickerView: View {
    // MARK: Internal

    let message: CustomMessage
    let chatVM: ChatVM

    var body: some View {
        NavigationStack {
            List {
                if normalizedQuery.isEmpty {
                    ForEach(recentChats) { chat in
                        chatRow(chat)
                    }
                } else {
                    ForEach(searchResults) { chat in
                        chatRow(chat)
                    }
                }
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

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selectedChatIds = Set<Int64>()
    @State private var isForwarding = false

    private var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var recentChats: [CustomChat] {
        allChats
            .sorted { lhs, rhs in
                let lhsDate = lhs.lastMessage?.date ?? 0
                let rhsDate = rhs.lastMessage?.date ?? 0
                if lhsDate != rhsDate {
                    return lhsDate > rhsDate
                }
                return lhs.position.order > rhs.position.order
            }
    }

    private var searchResults: [CustomChat] {
        allChats
            .filter { $0.displayTitle.localizedCaseInsensitiveContains(normalizedQuery) }
            .sorted { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
    }

    private var allChats: [CustomChat] {
        RootVM.shared.allChats
    }

    private func chatRow(_ chat: CustomChat) -> some View {
        Button {
            toggle(chat)
        } label: {
            HStack(spacing: 12) {
                ProfileImageView(
                    photo: chat.chat.photo?.small,
                    minithumbnail: chat.chat.photo?.minithumbnail,
                    title: chat.displayTitle,
                    userId: chat.chat.id,
                    fontSize: 18,
                    isSavedMessages: chat.isSavedMessages,
                )
                .frame(width: 40, height: 40)
                .accessibilityHidden(true)

                Text(chat.displayTitle)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer()

                Image(systemName: selectedChatIds.contains(chat.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selectedChatIds.contains(chat.id) ? Color.accentColor : .secondary)
                    .accessibilityHidden(true)
            }
        }
        .disabled(isForwarding)
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
