// ConferenceParticipantPicker.swift

import SwiftUI
@preconcurrency import TDLibKit

// MARK: - ConferenceParticipantPicker

/// Mirrors Telegram-iOS's single-selection "Add Member" conference picker. The current peer and
/// bots are excluded because TDLib can't invite either one as a new conference participant.
struct ConferenceParticipantPicker: View {
    // MARK: Lifecycle

    init(
        excludedUserId: Int64?,
        onSelect: @escaping (_ userId: Int64, _ isVideo: Bool) -> Void,
    ) {
        self.excludedUserId = excludedUserId
        self.onSelect = onSelect
    }

    // MARK: Internal

    var body: some View {
        List(filteredContacts) { user in
            HStack(spacing: 8) {
                Button {
                    select(user, isVideo: false)
                } label: {
                    HStack(spacing: 12) {
                        ProfileImageView(
                            photo: user.profilePhoto?.small,
                            minithumbnail: user.profilePhoto?.minithumbnail,
                            title: telegramUserDisplayName(user),
                            userId: user.id,
                        )
                        .frame(width: 44, height: 44)
                        .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(telegramUserDisplayName(user))
                                .font(.body.weight(.semibold))
                            Text(telegramUserPresenceDescription(user.status))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "phone.fill")
                            .foregroundStyle(.tint)
                            .accessibilityHidden(true)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add \(telegramUserDisplayName(user)) with audio")

                Button("Add \(telegramUserDisplayName(user)) with video", systemImage: "video.fill") {
                    select(user, isVideo: true)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
            }
            .disabled(selectedUserId != nil)
        }
        .overlay {
            if isLoading, contacts.isEmpty {
                ProgressView("Loading contacts…")
            } else if filteredContacts.isEmpty {
                ContentUnavailableView(
                    query.isEmpty ? "No Contacts" : "No Results",
                    systemImage: query.isEmpty ? "person.crop.circle.badge.xmark" : "magnifyingglass",
                )
            }
        }
        .navigationTitle("Add Member")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search contacts")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: dismiss.callAsFunction)
            }
        }
        .task {
            await loadContacts()
        }
        .alert("Contacts Error", isPresented: errorIsPresented) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @State private var contacts = [User]()
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var query = ""
    @State private var selectedUserId: Int64?

    private let excludedUserId: Int64?
    private let onSelect: (_ userId: Int64, _ isVideo: Bool) -> Void
    private let service: any TelegramService = TDLib.shared.service

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    errorMessage = nil
                }
            },
        )
    }

    private var filteredContacts: [User] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return contacts
            .filter { user in
                guard user.id != excludedUserId, user.haveAccess else { return false }
                guard case .userTypeRegular = user.type else { return false }
                guard !normalizedQuery.isEmpty else { return true }
                return telegramUserDisplayName(user)
                    .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                    .contains(normalizedQuery)
            }
            .sorted {
                telegramUserDisplayName($0)
                    .localizedStandardCompare(telegramUserDisplayName($1)) == .orderedAscending
            }
    }

    @MainActor private func loadContacts() async {
        guard contacts.isEmpty, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let userIds = try await service.getContacts().userIds
            var loadedContacts = [User]()
            for startIndex in stride(from: 0, to: userIds.count, by: 40) {
                let endIndex = min(startIndex + 40, userIds.count)
                let batch = Array(userIds[startIndex..<endIndex])
                await loadedContacts.append(contentsOf: batch.concurrentCompactMap { userId in
                    try? await service.getUser(userId: userId)
                })
                try Task.checkCancellation()
            }
            contacts = loadedContacts
        } catch is CancellationError {
            return
        } catch {
            errorMessage = telegramErrorDescription(error)
        }
    }

    private func select(_ user: User, isVideo: Bool) {
        guard selectedUserId == nil else { return }
        selectedUserId = user.id
        onSelect(user.id, isVideo)
        dismiss()
    }
}
