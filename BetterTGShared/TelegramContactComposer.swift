// TelegramContactComposer.swift

import SwiftUI
import TDLibKit

// MARK: - TelegramContactSourceKind

enum TelegramContactSourceKind: String, CaseIterable, Identifiable, Sendable {
    case existing
    case manual

    // MARK: Internal

    var id: Self { self }

    var title: String {
        switch self {
        case .existing: "My Contacts"
        case .manual: "New Contact"
        }
    }
}

// MARK: - TelegramContactDraft

struct TelegramContactDraft: Equatable {
    var sourceKind = TelegramContactSourceKind.existing
    var selectedEntry: TelegramContactPickerEntry?
    var firstName = ""
    var lastName = ""
    var phoneNumber = ""

    var isValid: Bool {
        (try? inputMessageContent()) != nil
    }

    func inputMessageContent() throws -> InputMessageContent {
        switch sourceKind {
        case .existing:
            guard let selectedEntry else {
                throw TelegramContactDraftValidationError.contactRequired
            }
            return .inputMessageContact(.init(contact: Contact(
                firstName: selectedEntry.firstName,
                lastName: selectedEntry.lastName,
                phoneNumber: selectedEntry.phoneNumber,
                userId: selectedEntry.userId,
                vcard: "",
            )))
        case .manual:
            let trimmedFirstName = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedLastName = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedPhoneNumber = phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedFirstName.isEmpty else {
                throw TelegramContactDraftValidationError.firstNameRequired
            }
            guard !trimmedPhoneNumber.isEmpty else {
                throw TelegramContactDraftValidationError.phoneNumberRequired
            }
            return .inputMessageContact(.init(contact: Contact(
                firstName: trimmedFirstName,
                lastName: trimmedLastName,
                phoneNumber: trimmedPhoneNumber,
                userId: 0,
                vcard: "",
            )))
        }
    }
}

// MARK: - TelegramContactDraftValidationError

enum TelegramContactDraftValidationError: Swift.Error, Equatable, LocalizedError {
    case contactRequired
    case firstNameRequired
    case phoneNumberRequired

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .contactRequired:
            "Choose a contact."
        case .firstNameRequired:
            "Enter a first name."
        case .phoneNumberRequired:
            "Enter a phone number."
        }
    }
}

// MARK: - TelegramContactSending

enum TelegramContactSending {
    @discardableResult static func send(
        draft: TelegramContactDraft,
        service: any TelegramService,
        chatId: Int64,
        replyToMessageId: Int64?,
        topicId: MessageTopic? = nil,
    ) async throws -> Message {
        let content = try draft.inputMessageContent()
        let messages = try await TelegramMessageSending.send(
            service: service,
            chatId: chatId,
            contents: [content],
            replyTo: TelegramMessageSending.replyTo(messageId: replyToMessageId),
            topicId: topicId,
            onAccepted: { messages in
                service.mergeMessages(chatId: chatId, messages: messages)
            },
        )
        guard let message = messages.first else {
            throw TelegramContactSendingError.noMessageReturned
        }
        return message
    }
}

// MARK: - TelegramContactSendingError

private enum TelegramContactSendingError: Swift.Error, LocalizedError {
    case noMessageReturned

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .noMessageReturned:
            "Telegram accepted the contact but didn't return the sent message."
        }
    }
}

// MARK: - TelegramContactComposerView

struct TelegramContactComposerView: View {
    // MARK: Lifecycle

    init(
        service: any TelegramService,
        deviceContactsAccessIsDenied: Bool = false,
        onOpenSettings: (() -> Void)? = nil,
        loadDeviceContacts: (@Sendable () async -> [DeviceContactRecord])? = nil,
        onSend: @escaping (TelegramContactDraft) async throws -> Void,
    ) {
        self.service = service
        self.deviceContactsAccessIsDenied = deviceContactsAccessIsDenied
        self.onOpenSettings = onOpenSettings
        self.loadDeviceContacts = loadDeviceContacts
        self.onSend = onSend
    }

    // MARK: Internal

    let service: any TelegramService
    /// Whether the device's system Contacts permission is denied - when true, this app's synced
    /// "My Contacts" list may be missing people from the phone's address book who are on
    /// Telegram, since `PermissionsManager.requestPostLoginPermissions()` (iOS-only) couldn't
    /// read them to sync. Passed in rather than checked here, since this view is shared with
    /// macOS, which has no such sync step.
    let deviceContactsAccessIsDenied: Bool
    let onOpenSettings: (() -> Void)?
    /// Reads the device's full address book (people without Telegram included) so they can still
    /// be shared, matching Telegram-iOS's own contact picker. `nil` on macOS, which has no device
    /// contacts sync of its own; `getContacts()`-known people still show either way.
    let loadDeviceContacts: (@Sendable () async -> [DeviceContactRecord])?
    let onSend: (TelegramContactDraft) async throws -> Void

    var body: some View {
        NavigationStack {
            Group {
                if draft.sourceKind == .existing {
                    existingContactsForm
                        .searchable(text: $query, prompt: "Search contacts")
                } else {
                    manualContactForm
                }
            }
            .navigationTitle("Share Contact")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", role: .cancel) { dismiss() }
                            .disabled(isSending)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Send") { send() }
                            .disabled(isSending || !draft.isValid)
                    }
                }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 520)
        #endif
        .task {
            guard !hasLoadedContacts else { return }
            hasLoadedContacts = true
            await loadContactsAndDeviceContacts()
        }
    }

    // MARK: Private

    @AccessibilityFocusState private var feedbackIsFocused: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var draft = TelegramContactDraft()
    @State private var telegramUsers = [User]()
    @State private var deviceContacts = [DeviceContactRecord]()
    @State private var query = ""
    @State private var isLoadingContacts = false
    @State private var hasLoadedContacts = false
    @State private var isSending = false
    @State private var feedbackMessage: String?

    private var entries: [TelegramContactPickerEntry] {
        telegramContactPickerEntries(telegramUsers: telegramUsers, deviceContacts: deviceContacts)
    }

    private var filteredEntries: [TelegramContactPickerEntry] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        guard !normalizedQuery.isEmpty else { return entries }
        return entries.filter { entry in
            let searchableText = [entry.displayName, entry.phoneNumber]
                .joined(separator: " ")
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            return searchableText.contains(normalizedQuery)
        }
    }

    private var sourcePickerSection: some View {
        Section {
            Picker("Source", selection: $draft.sourceKind) {
                ForEach(TelegramContactSourceKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)
        }
        .listRowInsets(EdgeInsets())
    }

    @ViewBuilder private var feedbackSection: some View {
        if isSending {
            Section { ProgressView("Sending contact") }
        }
        if let feedbackMessage {
            Section {
                Text(feedbackMessage)
                    .foregroundStyle(.red)
                    .accessibilityFocused($feedbackIsFocused)
            }
        }
    }

    @ViewBuilder private var deviceContactsAccessNotice: some View {
        if deviceContactsAccessIsDenied {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Contacts Access Is Off")
                        .font(.subheadline.weight(.semibold))
                    Text("Turn on Contacts access in Settings to find more people from your phone on Telegram.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let onOpenSettings {
                        Button("Open Settings", action: onOpenSettings)
                    }
                }
            }
        }
    }

    private var existingContactsForm: some View {
        Form {
            sourcePickerSection

            deviceContactsAccessNotice

            Section("My Contacts") {
                if isLoadingContacts, entries.isEmpty {
                    ProgressView("Loading contacts")
                } else if filteredEntries.isEmpty {
                    Text(query.isEmpty ? "No contacts" : "No matching contacts")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filteredEntries) { entry in
                        contactRow(entry)
                    }
                }
            }

            feedbackSection
        }
    }

    private var manualContactForm: some View {
        Form {
            sourcePickerSection

            Section("Name") {
                TextField("First Name", text: $draft.firstName)
                TextField("Last Name", text: $draft.lastName)
            }

            Section("Phone") {
                TextField("Phone Number", text: $draft.phoneNumber)
                    #if os(iOS)
                    .keyboardType(.phonePad)
                    #endif
            }

            feedbackSection
        }
    }

    private func contactRow(_ entry: TelegramContactPickerEntry) -> some View {
        let isSelected = draft.selectedEntry?.id == entry.id
        return Button {
            draft.selectedEntry = entry
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.displayName)
                    HStack(spacing: 4) {
                        if !entry.phoneNumber.isEmpty {
                            Text(entry.phoneNumber)
                        }
                        if entry.isOnTelegram {
                            Text("· On Telegram")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    @MainActor private func loadContactsAndDeviceContacts() async {
        isLoadingContacts = true
        defer { isLoadingContacts = false }
        async let telegramResult = loadTelegramUsers()
        async let deviceResult = loadDeviceContacts?() ?? []
        telegramUsers = await telegramResult
        deviceContacts = await deviceResult
    }

    private func loadTelegramUsers() async -> [User] {
        guard let result = try? await service.getContacts() else { return [] }
        var loaded = [User]()
        for userId in result.userIds {
            if let user = try? await service.getUser(userId: userId) {
                loaded.append(user)
            }
        }
        return loaded
    }

    private func send() {
        feedbackMessage = nil
        feedbackIsFocused = false
        do {
            _ = try draft.inputMessageContent()
        } catch {
            feedbackMessage = telegramErrorDescription(error)
            feedbackIsFocused = true
            return
        }

        isSending = true
        Task {
            do {
                try await onSend(draft)
                dismiss()
            } catch {
                isSending = false
                feedbackMessage = telegramErrorDescription(error)
                feedbackIsFocused = true
            }
        }
    }
}
