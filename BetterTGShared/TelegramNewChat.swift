// TelegramNewChat.swift

import PhotosUI
import SwiftUI
@preconcurrency import TDLibKit

#if os(iOS)
import UIKit
#else
import AppKit
#endif

// MARK: - TelegramNewChatMenu

/// The chat list's "+" button - matches official Telegram's own new-chat menu.
struct TelegramNewChatMenu: View {
    // MARK: Internal

    let service: any TelegramService
    let onCreated: (Chat) -> Void

    var body: some View {
        Menu {
            Button {
                showsNewChat = true
            } label: {
                Label("New Chat", systemImage: "person")
            }
            Button {
                showsNewSecretChat = true
            } label: {
                Label("New Secret Chat", systemImage: "lock")
            }
            Button {
                showsNewGroup = true
            } label: {
                Label("New Group", systemImage: "person.3")
            }
            Button {
                showsNewChannel = true
            } label: {
                Label("New Channel", systemImage: "megaphone")
            }
        } label: {
            Label("New Chat", systemImage: "square.and.pencil")
                .labelStyle(.iconOnly)
        }
        .sheet(isPresented: $showsNewChat) {
            NewPrivateChatView(service: service, kind: .regular) { chat in
                showsNewChat = false
                onCreated(chat)
            }
        }
        .sheet(isPresented: $showsNewSecretChat) {
            NewPrivateChatView(service: service, kind: .secret) { chat in
                showsNewSecretChat = false
                onCreated(chat)
            }
        }
        .sheet(isPresented: $showsNewGroup) {
            NewGroupView(service: service) { chat in
                showsNewGroup = false
                onCreated(chat)
            }
        }
        .sheet(isPresented: $showsNewChannel) {
            NewChannelView(service: service) { chat in
                showsNewChannel = false
                onCreated(chat)
            }
        }
    }

    // MARK: Private

    @State private var showsNewChannel = false
    @State private var showsNewChat = false
    @State private var showsNewGroup = false
    @State private var showsNewSecretChat = false
}

// MARK: - NewPrivateChatView

/// Single-select contact picker shared by "New Chat" and "New Secret Chat" - the only difference
/// between the two is which TDLib call fires once a contact is tapped.
struct NewPrivateChatView: View {
    // MARK: Internal

    enum Kind {
        case regular
        case secret

        // MARK: Internal

        var title: String {
            switch self {
            case .regular: "New Chat"
            case .secret: "New Secret Chat"
            }
        }
    }

    let service: any TelegramService
    let kind: Kind
    let onCreated: (Chat) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(filteredContacts) { user in
                        userRow(user)
                    }
                } header: {
                    if !isSearching {
                        EmptyView()
                    } else if !filteredContacts.isEmpty {
                        Text("Contacts")
                    }
                }

                if isSearching {
                    Section {
                        ForEach(globalResults) { user in
                            userRow(user)
                        }
                        if isSearchingGlobally {
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                        }
                    } header: {
                        if !globalResults.isEmpty {
                            Text("Global Search")
                        }
                    }
                }
            }
            .overlay {
                if isLoadingContacts, contacts.isEmpty {
                    ProgressView()
                } else if !isSearching, contacts.isEmpty {
                    ContentUnavailableView("No Contacts", systemImage: "person.crop.circle.badge.xmark")
                } else if isSearching, filteredContacts.isEmpty, globalResults.isEmpty, !isSearchingGlobally {
                    ContentUnavailableView.search(text: query)
                }
            }
            .searchable(text: $query, prompt: "Search by name or username")
            .navigationTitle(kind.title)
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
        }
        .task {
            guard !hasLoadedContacts else { return }
            hasLoadedContacts = true
            await loadContacts()
        }
        .task(id: normalizedQuery) {
            await searchGlobally()
        }
        .alert("Couldn't Start Chat", isPresented: errorIsPresented) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss

    @State private var contacts = [User]()
    @State private var creatingUserId: Int64?
    @State private var errorMessage: String?
    @State private var globalResults = [User]()
    @State private var hasLoadedContacts = false
    @State private var isLoadingContacts = false
    @State private var isSearchingGlobally = false
    @State private var query = ""

    private var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearching: Bool {
        !normalizedQuery.isEmpty
    }

    private var filteredContacts: [User] {
        guard isSearching else { return contacts }
        return contacts.filter { user in
            let searchableText = ([telegramUserDisplayName(user)] + (user.usernames?.activeUsernames ?? []))
                .joined(separator: " ")
            return searchableText.localizedCaseInsensitiveContains(normalizedQuery)
        }
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

    private func userRow(_ user: User) -> some View {
        Button {
            Task { await start(with: user) }
        } label: {
            HStack {
                Text(telegramUserDisplayName(user))
                    .foregroundStyle(.primary)
                Spacer()
                if creatingUserId == user.id {
                    ProgressView()
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(creatingUserId != nil)
    }

    @MainActor private func loadContacts() async {
        isLoadingContacts = true
        defer { isLoadingContacts = false }
        guard let result = try? await service.getContacts() else { return }
        contacts = await result.userIds
            .concurrentCompactMap { try? await service.getUser(userId: $0) }
            .sorted {
                telegramUserDisplayName($0).localizedStandardCompare(telegramUserDisplayName($1)) == .orderedAscending
            }
    }

    /// Server-side search for people not already in the local contact list - matches the official
    /// app's own New Chat search, which finds any Telegram user by name/username, not just
    /// contacts. `searchPublicChats` only surfaces chats *not* already known/contacts, so results
    /// here never duplicate `filteredContacts`.
    @MainActor private func searchGlobally() async {
        let contactIds = Set(contacts.map(\.id))
        guard isSearching else {
            globalResults = []
            return
        }
        isSearchingGlobally = true
        defer { isSearchingGlobally = false }
        guard let result = try? await service.searchPublicChats(query: normalizedQuery, typeFilter: nil) else {
            globalResults = []
            return
        }
        let chats = await result.chatIds.concurrentCompactMap { try? await service.getChat(chatId: $0) }
        let userIds = chats.compactMap { chat -> Int64? in
            guard case .chatTypePrivate(let value) = chat.type, !contactIds.contains(value.userId) else { return nil }
            return value.userId
        }
        globalResults = await userIds.concurrentCompactMap { try? await service.getUser(userId: $0) }
    }

    @MainActor private func start(with user: User) async {
        guard creatingUserId == nil else { return }
        creatingUserId = user.id
        defer { creatingUserId = nil }
        do {
            let chat =
                switch kind {
                case .regular: try await service.createPrivateChat(force: false, userId: user.id)
                case .secret: try await service.createNewSecretChat(userId: user.id)
                }
            onCreated(chat)
        } catch {
            errorMessage = telegramErrorDescription(error)
        }
    }
}

// MARK: - NewGroupView

struct NewGroupView: View {
    // MARK: Lifecycle

    init(service: any TelegramService, onCreated: @escaping (Chat) -> Void) {
        self.service = service
        self.onCreated = onCreated
    }

    // MARK: Internal

    let service: any TelegramService
    let onCreated: (Chat) -> Void

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .selectMembers:
                    memberSelectionList
                case .details:
                    detailsForm
                }
            }
            .navigationTitle(step == .selectMembers ? "Add Members" : "New Group")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            if step == .details {
                                step = .selectMembers
                            } else {
                                dismiss()
                            }
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        switch step {
                        case .selectMembers:
                            Button("Next") { step = .details }
                                .disabled(selectedUserIds.isEmpty)
                        case .details:
                            if isCreating {
                                ProgressView()
                            } else {
                                Button("Create") { Task { await create() } }
                                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }
                    }
                }
        }
        .task {
            guard !hasLoadedContacts else { return }
            hasLoadedContacts = true
            await loadContacts()
        }
        .onChange(of: pickedPhotoItem) { _, newValue in
            Task { await loadPickedPhoto(newValue) }
        }
        .alert("Couldn't Create Group", isPresented: errorIsPresented) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Private

    private enum Step {
        case selectMembers
        case details
    }

    @Environment(\.dismiss) private var dismiss

    @State private var contacts = [User]()
    @State private var errorMessage: String?
    @State private var hasLoadedContacts = false
    @State private var isCreating = false
    @State private var isLoadingContacts = false
    @State private var pendingPhotoData: Data?
    @State private var pickedPhotoItem: PhotosPickerItem?
    @State private var selectedUserIds = Set<Int64>()
    @State private var step = Step.selectMembers
    @State private var title = ""

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

    private var memberSelectionList: some View {
        List(contacts) { user in
            Button {
                toggle(user.id)
            } label: {
                HStack {
                    Text(telegramUserDisplayName(user))
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: selectedUserIds.contains(user.id) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selectedUserIds.contains(user.id) ? Color.accentColor : .secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .overlay {
            if isLoadingContacts, contacts.isEmpty {
                ProgressView()
            } else if contacts.isEmpty {
                ContentUnavailableView("No Contacts", systemImage: "person.crop.circle.badge.xmark")
            }
        }
    }

    private var detailsForm: some View {
        Form {
            Section {
                photoPicker
                TextField("Group Name", text: $title)
            } footer: {
                Text("\(selectedUserIds.count) member\(selectedUserIds.count == 1 ? "" : "s") selected.")
            }

            if isCreating {
                Section {
                    ProgressView("Creating…")
                }
            }
        }
    }

    private var photoPicker: some View {
        HStack {
            Spacer()
            VStack(spacing: 10) {
                groupPhotoPreview
                PhotosPicker(selection: $pickedPhotoItem, matching: .images) {
                    Text(pendingPhotoData == nil ? "Add Photo" : "Change Photo")
                }
            }
            Spacer()
        }
        .padding(.vertical, 8)
    }

    private var groupPhotoPreview: some View {
        ZStack {
            if let pendingPhotoData, let image = Image(chatPhotoData: pendingPhotoData) {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                Circle()
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: "person.3.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .frame(width: 88, height: 88)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private func toggle(_ userId: Int64) {
        if !selectedUserIds.insert(userId).inserted {
            selectedUserIds.remove(userId)
        }
    }

    @MainActor private func loadContacts() async {
        isLoadingContacts = true
        defer { isLoadingContacts = false }
        guard let result = try? await service.getContacts() else { return }
        contacts = await result.userIds
            .concurrentCompactMap { try? await service.getUser(userId: $0) }
            .sorted {
                telegramUserDisplayName($0).localizedStandardCompare(telegramUserDisplayName($1)) == .orderedAscending
            }
    }

    @MainActor private func loadPickedPhoto(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self) else { return }
        pendingPhotoData = data
    }

    @MainActor private func create() async {
        isCreating = true
        defer { isCreating = false }
        do {
            let created = try await service.createNewBasicGroupChat(
                messageAutoDeleteTime: 0,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                userIds: Array(selectedUserIds),
            )
            if let pendingPhotoData {
                await telegramUploadChatPhoto(pendingPhotoData, chatId: created.chatId, service: service)
            }
            guard let chat = try? await service.getChat(chatId: created.chatId) else {
                dismiss()
                return
            }
            onCreated(chat)
        } catch {
            errorMessage = telegramErrorDescription(error)
        }
    }
}

// MARK: - NewChannelView

struct NewChannelView: View {
    // MARK: Lifecycle

    init(service: any TelegramService, onCreated: @escaping (Chat) -> Void) {
        self.service = service
        self.onCreated = onCreated
    }

    // MARK: Internal

    let service: any TelegramService
    let onCreated: (Chat) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    photoPicker
                    TextField("Channel Name", text: $title)
                    TextField("Description (optional)", text: $channelDescription, axis: .vertical)
                }

                Section {
                    Picker("Visibility", selection: $isPublic) {
                        Text("Public").tag(true)
                        Text("Private").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    if isPublic {
                        TextField("Username", text: $username)
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                            .autocorrectionDisabled()
                    }
                } footer: {
                    Text(
                        isPublic
                            ? "People can find this channel by its username and share it as a link."
                            : "Only people with an invite link can join this channel.",
                    )
                }

                if let usernameStatusText {
                    Section {
                        Text(usernameStatusText)
                            .font(.footnote)
                            .foregroundStyle(usernameIsAvailable == true ? .secondary : Color.red)
                    }
                }

                if isCreating {
                    Section {
                        ProgressView("Creating…")
                    }
                }
            }
            .navigationTitle("New Channel")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        if isCreating {
                            ProgressView()
                        } else {
                            Button("Create") { Task { await create() } }
                                .disabled(!canCreate)
                        }
                    }
                }
        }
        .onChange(of: pickedPhotoItem) { _, newValue in
            Task { await loadPickedPhoto(newValue) }
        }
        .task(id: username) {
            await checkUsername()
        }
        .alert("Couldn't Create Channel", isPresented: errorIsPresented) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss

    @State private var channelDescription = ""
    @State private var errorMessage: String?
    @State private var isChecking = false
    @State private var isCreating = false
    @State private var isPublic = false
    @State private var pendingPhotoData: Data?
    @State private var pickedPhotoItem: PhotosPickerItem?
    @State private var title = ""
    @State private var username = ""
    @State private var usernameIsAvailable: Bool?

    private var canCreate: Bool {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !isCreating else { return false }
        guard isPublic else { return true }
        return !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && usernameIsAvailable == true
    }

    private var usernameStatusText: String? {
        guard isPublic, !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        if isChecking {
            return "Checking availability…"
        }
        switch usernameIsAvailable {
        case true: return "This username is available."
        case false: return "This username is already taken or invalid."
        case nil: return nil
        }
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

    private var photoPicker: some View {
        HStack {
            Spacer()
            VStack(spacing: 10) {
                channelPhotoPreview
                PhotosPicker(selection: $pickedPhotoItem, matching: .images) {
                    Text(pendingPhotoData == nil ? "Add Photo" : "Change Photo")
                }
            }
            Spacer()
        }
        .padding(.vertical, 8)
    }

    private var channelPhotoPreview: some View {
        ZStack {
            if let pendingPhotoData, let image = Image(chatPhotoData: pendingPhotoData) {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                Circle()
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: "megaphone.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .frame(width: 88, height: 88)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    @MainActor private func loadPickedPhoto(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self) else { return }
        pendingPhotoData = data
    }

    @MainActor private func checkUsername() async {
        let normalizedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isPublic, !normalizedUsername.isEmpty else {
            usernameIsAvailable = nil
            return
        }
        isChecking = true
        defer { isChecking = false }
        guard let result = try? await service.checkChatUsername(chatId: 0, username: normalizedUsername) else {
            usernameIsAvailable = nil
            return
        }
        usernameIsAvailable = result == .checkChatUsernameResultOk
    }

    @MainActor private func create() async {
        isCreating = true
        defer { isCreating = false }
        do {
            let chat = try await service.createNewSupergroupChat(
                description: channelDescription.trimmingCharacters(in: .whitespacesAndNewlines),
                forImport: false,
                isChannel: true,
                isForum: false,
                location: nil,
                messageAutoDeleteTime: 0,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            )
            if isPublic, case .chatTypeSupergroup(let supergroup) = chat.type {
                _ = try? await service.setSupergroupUsername(
                    supergroupId: supergroup.supergroupId,
                    username: username.trimmingCharacters(in: .whitespacesAndNewlines),
                )
            }
            if let pendingPhotoData {
                await telegramUploadChatPhoto(pendingPhotoData, chatId: chat.id, service: service)
            }
            onCreated(chat)
        } catch {
            errorMessage = telegramErrorDescription(error)
        }
    }
}

// MARK: - Shared helpers

/// Writes the picked image to a temp file and hands it to TDLib - `setChatPhoto` (like
/// `setProfilePhoto`) needs a real file path, not raw `Data`. Deliberately swallows failures: a
/// group/channel already exists by the time this runs, so a photo upload failure shouldn't block
/// finishing the creation flow.
@MainActor func telegramUploadChatPhoto(_ data: Data, chatId: Int64, service: any TelegramService) async {
    let fileURL = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).jpeg")
    guard (try? data.write(to: fileURL)) != nil else { return }
    defer { try? FileManager.default.removeItem(at: fileURL) }
    _ = try? await service.setChatPhoto(
        chatId: chatId,
        photo: .inputChatPhotoStatic(InputChatPhotoStatic(photo: .inputFileLocal(InputFileLocal(path: fileURL.path)))),
    )
}

private extension Image {
    /// Same reasoning as `TelegramProfileSettings.swift`'s own private copy of this initializer -
    /// a small platform-decoding branch kept local to whichever file needs it, not centralized in
    /// the iOS-only `BetterTG/Extensions/Image+.swift`.
    init?(chatPhotoData data: Data) {
        #if os(iOS)
        guard let uiImage = UIImage(data: data) else { return nil }
        self.init(uiImage: uiImage)
        #else
        guard let nsImage = NSImage(data: data) else { return nil }
        self.init(nsImage: nsImage)
        #endif
    }
}
