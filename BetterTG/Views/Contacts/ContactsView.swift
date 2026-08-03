// ContactsView.swift

import SwiftUI
import TDLibKit

// MARK: - ContactsView

struct ContactsView: View {
    // MARK: Lifecycle

    init(service: any TelegramService) {
        self.service = service
    }

    // MARK: Internal

    var body: some View {
        List {
            ForEach(sortedContacts) { user in
                Button {
                    Task { await openChat(with: user) }
                } label: {
                    ContactRow(user: user, isOpening: openingUserId == user.id)
                }
                .buttonStyle(.plain)
                .disabled(openingUserId != nil)
            }
        }
        .overlay {
            if isLoading, contacts.isEmpty {
                ProgressView("Loading contacts…")
            } else if sortedContacts.isEmpty {
                ContentUnavailableView(
                    query.isEmpty ? "No Contacts" : "No Results",
                    systemImage: query.isEmpty ? "person.crop.circle.badge.xmark" : "magnifyingglass",
                    description: Text(
                        query.isEmpty
                            ? "Your Telegram contacts will appear here."
                            : "No contacts match your search.",
                    ),
                )
            }
        }
        .navigationTitle("Contacts")
        .searchable(
            text: $query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search contacts",
        )
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu("Sort") {
                    Picker("Sort Contacts", selection: sortOrderBinding) {
                        Label("Last Seen", systemImage: "clock")
                            .tag(ContactsSortOrder.presence)
                        Label("Name", systemImage: "textformat")
                            .tag(ContactsSortOrder.name)
                    }
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button("Add Contact", systemImage: "plus") {
                    showsNewContact = true
                }
                .labelStyle(.iconOnly)
            }
        }
        .sheet(isPresented: $showsNewContact) {
            NavigationStack {
                NewContactView(service: service) {
                    Task { await loadContacts(showsProgress: false) }
                }
            }
        }
        .task {
            guard contacts.isEmpty else { return }
            await loadContacts(showsProgress: true)
        }
        .refreshable {
            await loadContacts(showsProgress: false)
        }
        .onReceive(service.updatePublisher) { update in
            handle(update)
        }
        .alert("Contacts Error", isPresented: errorIsPresented) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Private

    private enum ContactsSortOrder: String {
        case presence
        case name
    }

    @AppStorage("contactsSortOrder") private var storedSortOrder = ContactsSortOrder.presence.rawValue
    @Bindable private var rootVM = RootVM.shared
    @State private var contacts = [User]()
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var openingUserId: Int64?
    @State private var query = ""
    @State private var showsNewContact = false

    private let service: any TelegramService

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

    private var sortOrder: ContactsSortOrder {
        ContactsSortOrder(rawValue: storedSortOrder) ?? .presence
    }

    private var sortOrderBinding: Binding<ContactsSortOrder> {
        Binding(
            get: { sortOrder },
            set: { storedSortOrder = $0.rawValue },
        )
    }

    private var sortedContacts: [User] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let filtered = contacts.filter { user in
            guard !normalizedQuery.isEmpty else { return true }
            let searchableText = [
                telegramUserDisplayName(user),
                user.phoneNumber,
                user.usernames?.activeUsernames.joined(separator: " ") ?? "",
            ]
                .joined(separator: " ")
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            return searchableText.contains(normalizedQuery)
        }

        let now = Int64(Date().timeIntervalSince1970)
        return filtered.sorted { lhs, rhs in
            if sortOrder == .presence {
                let lhsPresence = presenceSortValue(lhs.status, now: now)
                let rhsPresence = presenceSortValue(rhs.status, now: now)
                if lhsPresence != rhsPresence {
                    return lhsPresence > rhsPresence
                }
            }
            return telegramUserDisplayName(lhs)
                .localizedStandardCompare(telegramUserDisplayName(rhs)) == .orderedAscending
        }
    }

    @MainActor private func loadContacts(showsProgress: Bool) async {
        if showsProgress {
            isLoading = true
        }
        defer { isLoading = false }

        do {
            let result = try await service.getContacts()
            var loadedContacts = [User]()
            for startIndex in stride(from: 0, to: result.userIds.count, by: 40) {
                let endIndex = min(startIndex + 40, result.userIds.count)
                let batch = Array(result.userIds[startIndex..<endIndex])
                await loadedContacts.append(contentsOf: batch.concurrentCompactMap { userId in
                    try? await service.getUser(userId: userId)
                })
                await Task.yield()
            }
            contacts = loadedContacts
        } catch {
            errorMessage = telegramErrorDescription(error)
        }
    }

    @MainActor private func openChat(with user: User) async {
        guard openingUserId == nil else { return }
        openingUserId = user.id
        defer { openingUserId = nil }

        do {
            let chat = try await service.createPrivateChat(force: false, userId: user.id)
            guard let customChat = await rootVM.getCustomChat(from: chat.id) else {
                errorMessage = "The conversation couldn't be opened."
                return
            }
            rootVM.navigate(to: .customChat(customChat))
        } catch {
            errorMessage = telegramErrorDescription(error)
        }
    }

    @MainActor private func handle(_ update: Update) {
        switch update {
        case .updateUser(let value):
            if value.user.isContact {
                replaceOrAppend(value.user)
            } else {
                contacts.removeAll { $0.id == value.user.id }
            }
        case .updateUserStatus(let value):
            guard contacts.contains(where: { $0.id == value.userId }) else { return }
            Task {
                guard let user = try? await service.getUser(userId: value.userId) else { return }
                replaceOrAppend(user)
            }
        default:
            break
        }
    }

    @MainActor private func replaceOrAppend(_ user: User) {
        if let index = contacts.firstIndex(where: { $0.id == user.id }) {
            contacts[index] = user
        } else {
            contacts.append(user)
        }
    }

    private func presenceSortValue(_ status: UserStatus, now: Int64) -> Int64 {
        switch status {
        case .userStatusOnline:
            Int64.max
        case .userStatusRecently:
            now - (3 * 24 * 60 * 60)
        case .userStatusOffline(let value):
            Int64(value.wasOnline)
        case .userStatusLastWeek:
            now - (7 * 24 * 60 * 60)
        case .userStatusLastMonth:
            now - (30 * 24 * 60 * 60)
        case .userStatusEmpty:
            0
        }
    }
}

// MARK: - ContactRow

private struct ContactRow: View {
    // MARK: Internal

    let user: User
    let isOpening: Bool

    var body: some View {
        HStack(spacing: 12) {
            ProfileImageView(
                photo: user.profilePhoto?.small,
                minithumbnail: user.profilePhoto?.minithumbnail,
                title: telegramUserDisplayName(user),
                userId: user.id,
            )
            .frame(width: 46, height: 46)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(telegramUserDisplayName(user))
                    .font(.body.weight(.semibold))
                Text(telegramUserPresenceDescription(user.status))
                    .font(.subheadline)
                    .foregroundStyle(isOnline ? Color.accentColor : Color.secondary)
            }

            Spacer()

            if isOpening {
                ProgressView()
            }
        }
        .contentShape(.rect)
    }

    // MARK: Private

    private var isOnline: Bool {
        if case .userStatusOnline = user.status {
            return true
        }
        return false
    }
}

// MARK: - NewContactView

private struct NewContactView: View {
    // MARK: Lifecycle

    init(service: any TelegramService, onAdded: @escaping () -> Void) {
        self.service = service
        self.onAdded = onAdded
    }

    // MARK: Internal

    var body: some View {
        Form {
            Section("Name") {
                TextField("First Name", text: $firstName)
                    .textContentType(.givenName)
                TextField("Last Name", text: $lastName)
                    .textContentType(.familyName)
            }

            Section("Phone") {
                TextField("Phone Number", text: $phoneNumber)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
            }
        }
        .navigationTitle("New Contact")
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(isSaving)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
                .disabled(isSaving)
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Add") {
                    Task { await addContact() }
                }
                .disabled(!canAdd || isSaving)
            }
        }
        .alert("Contact couldn't be added", isPresented: errorIsPresented) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?
    @State private var firstName = ""
    @State private var isSaving = false
    @State private var lastName = ""
    @State private var phoneNumber = ""

    private let onAdded: () -> Void
    private let service: any TelegramService

    private var canAdd: Bool {
        !firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

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

    @MainActor private func addContact() async {
        guard canAdd else { return }
        isSaving = true
        defer { isSaving = false }

        let contact = ImportedContact(
            firstName: firstName.trimmingCharacters(in: .whitespacesAndNewlines),
            lastName: lastName.trimmingCharacters(in: .whitespacesAndNewlines),
            note: nil,
            phoneNumber: phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines),
        )

        do {
            let result = try await service.importContacts(contacts: [contact])
            guard result.userIds.first.map({ $0 != 0 }) == true else {
                errorMessage = "No Telegram account was found for this phone number."
                return
            }
            onAdded()
            dismiss()
        } catch {
            errorMessage = telegramErrorDescription(error)
        }
    }
}
