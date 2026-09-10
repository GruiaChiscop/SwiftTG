// TelegramProfileSettings.swift

import PhotosUI
import SwiftUI
import TDLibKit

// MARK: - EditProfileMode

enum EditProfileMode: String, Hashable, Identifiable {
    case all
    case photo
    case name
    case bio

    // MARK: Internal

    var id: Self { self }

    var navigationTitle: String {
        switch self {
        case .all:
            "Edit Profile"
        case .photo:
            "Profile Photo"
        case .name:
            "Change Name"
        case .bio:
            "Edit Bio"
        }
    }
}

// MARK: - EditProfileView

struct EditProfileView: View {
    // MARK: Lifecycle

    init(
        service: any TelegramService,
        showsCancelButton: Bool = false,
        mode: EditProfileMode = .all,
    ) {
        self.service = service
        self.showsCancelButton = showsCancelButton
        self.mode = mode
    }

    // MARK: Internal

    var body: some View {
        NavigationStack {
            form
                .navigationTitle(mode.navigationTitle)
                #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                #endif
                    .toolbar {
                        if showsCancelButton {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel", role: .cancel) { dismiss() }
                            }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") { Task { await save() } }
                                .disabled(!canSave)
                        }
                    }
        }
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            await loadProfile()
        }
        .onChange(of: pickedPhotoItem) { _, newValue in
            Task { await loadPickedPhoto(newValue) }
        }
        .alert("Couldn't Update Profile", isPresented: errorIsPresented) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
        .alert(
            "Username Already Taken",
            isPresented: Binding(
                get: { fragmentUsernameOffer != nil },
                set: { isPresented in
                    if !isPresented {
                        fragmentUsernameOffer = nil
                    }
                },
            ),
            presenting: fragmentUsernameOffer,
        ) { offeredUsername in
            Button("View on Fragment") {
                if let url = URL(string: "https://fragment.com/username/\(offeredUsername)") {
                    openURL(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This username is already taken, but it's currently available for purchase on Fragment.")
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var bio = ""
    @State private var errorMessage: String?
    @State private var firstName = ""
    @State private var fragmentUsernameOffer: String?
    @State private var hasLoaded = false
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var lastName = ""
    @State private var loaded: LoadedProfile?
    @State private var pendingPhotoData: Data?
    @State private var photoData: Data?
    @State private var pickedPhotoItem: PhotosPickerItem?
    @State private var username = ""

    private let service: any TelegramService
    private let showsCancelButton: Bool
    private let mode: EditProfileMode

    private var canSave: Bool {
        guard !isSaving, !firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return isDirty
    }

    private var isDirty: Bool {
        guard let loaded else { return false }
        return firstName != loaded.firstName
            || lastName != loaded.lastName
            || bio != loaded.bio
            || username != loaded.username
            || pendingPhotoData != nil
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

    private var form: some View {
        Form {
            if mode == .all {
                Section {
                    photoSection
                    TextField("First name", text: $firstName)
                    TextField("Last name", text: $lastName)
                } footer: {
                    Text("Enter your name and add an optional profile photo.")
                }
            } else if mode == .photo {
                Section {
                    photoSection
                } footer: {
                    Text("Choose a photo that represents you in calls and conversations.")
                }
            } else if mode == .name {
                Section {
                    TextField("First name", text: $firstName)
                    TextField("Last name", text: $lastName)
                } footer: {
                    Text("Enter your first name and an optional last name.")
                }
            }

            if mode == .all || mode == .bio {
                Section {
                    TextField("Bio", text: $bio, axis: .vertical)
                } header: {
                    Text("Bio")
                } footer: {
                    Text("Any details such as age, occupation or city.\nExample: 23 y.o. designer from London.")
                }
            }

            if mode == .all {
                Section {
                    Text("@")
                    TextField("Username", text: $username)
                        .autocorrectionDisabled(true)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                } header: {
                    Text("Username")
                } footer: {
                    // Matches Telegram-iOS's Username.Help string verbatim (en.lproj/Localizable.strings).
                    Text(
                        "You can choose a username on **Telegram**. If you do, other people will be able to find you by this username and contact you without knowing your phone number.\n\nYou can use **a-z**, **0-9** and underscores. Minimum length is **5** characters.",
                    )
                }
            }

            if isSaving {
                Section {
                    ProgressView("Saving…")
                }
            }
        }
    }

    private var photoSection: some View {
        let hasPhoto = photoData != nil || pendingPhotoData != nil
        return HStack {
            Spacer()
            VStack(spacing: 10) {
                ZStack {
                    if let previewData = pendingPhotoData ?? photoData,
                       let image = Image(profilePhotoData: previewData)
                    {
                        image
                            .resizable()
                            .scaledToFill()
                    } else {
                        Circle()
                            .fill(.quaternary)
                            .overlay {
                                Image(systemName: "person.fill")
                                    .font(.system(size: 36))
                                    .foregroundStyle(.secondary)
                            }
                    }
                }
                .frame(width: 96, height: 96)
                .clipShape(Circle())
                .accessibilityHidden(true)

                PhotosPicker(selection: $pickedPhotoItem, matching: .images) {
                    Text(hasPhoto ? "Change Photo" : "Add Photo")
                }
            }
            Spacer()
        }
        .padding(.vertical, 8)
    }

    /// Mirrors Telegram-iOS's local `_internal_checkAddressNameFormat`. An empty string is
    /// allowed - it clears the username.
    private static func usernameFormatIssue(_ value: String) -> UsernameFormatIssue? {
        guard !value.isEmpty else { return nil }
        guard value.count >= 5 else { return .tooShort }
        guard let first = value.first else { return nil }
        if first == "_" {
            return .startsWithUnderscore
        }
        if first >= "0", first <= "9" {
            return .startsWithNumber
        }
        if value.hasSuffix("_") {
            return .endsWithUnderscore
        }
        let allowed = CharacterSet(
            charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_",
        )
        if value.unicodeScalars.contains(where: { !allowed.contains($0) }) {
            return .invalidCharacters
        }
        return nil
    }

    /// Maps the raw Telegram/TDLib error strings that `setProfilePhoto`/`setName`/`setBio`/
    /// `setUsername` can throw to readable text. `USERNAME_PURCHASE_AVAILABLE` is handled at the
    /// call site instead, with its own Fragment alert.
    private static func editProfileErrorMessage(_ error: Swift.Error) -> String {
        guard let error = error as? TDLibKit.Error else {
            return telegramErrorDescription(error)
        }
        let message = error.message.trimmingCharacters(in: .whitespacesAndNewlines)
        if error.code == 429 || message.hasPrefix("FLOOD_WAIT") || message.hasPrefix("Too Many Requests") {
            return "You're doing that too often. Please wait a moment and try again."
        }
        switch message {
        case "USERNAME_INVALID":
            return "This username isn't valid. Use 5–32 letters, numbers or underscores, and don't start with a number."
        case "USERNAME_OCCUPIED":
            return "This username is already taken. Please choose another."
        case "USERNAMES_ACTIVE_TOO_MUCH":
            return "You already have the maximum number of active usernames. Remove one before adding another."
        case "ABOUT_NOT_MODIFIED", "NAME_NOT_MODIFIED", "USERNAME_NOT_MODIFIED":
            return "That's already your current profile - nothing to update."
        case "FIRSTNAME_INVALID":
            return "That first name isn't valid. Please try a different one."
        case "LASTNAME_INVALID":
            return "That last name isn't valid. Please try a different one."
        case "ABOUT_TOO_LONG":
            return "Your bio is too long. Please shorten it and try again."
        case "PHOTO_CONTENT_TYPE_INVALID", "PHOTO_EXT_INVALID", "PHOTO_FILE_MISSING":
            return "That file isn't a supported image. Please pick a different photo."
        case "PHOTO_CROP_SIZE_SMALL", "PHOTO_INVALID_DIMENSIONS":
            return "That image is too small to use as a profile photo. Please pick a larger one."
        case "IMAGE_PROCESS_FAILED":
            return "Telegram couldn't process that image. Please try a different photo."
        default:
            return telegramErrorDescription(error)
        }
    }

    @MainActor private func loadProfile() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let user = try await service.getMe()
            let profile = await LoadedProfile(
                firstName: user.firstName,
                lastName: user.lastName,
                bio: (try? service.getUserFullInfo(userId: user.id))?.bio?.text ?? "",
                username: user.usernames?.editableUsername ?? "",
            )
            loaded = profile
            firstName = profile.firstName
            lastName = profile.lastName
            bio = profile.bio
            username = profile.username
            if let smallPhotoId = user.profilePhoto?.small.id {
                photoData = await downloadedPhotoData(fileId: smallPhotoId)
            }
        } catch {
            errorMessage = telegramErrorDescription(error)
        }
    }

    private func downloadedPhotoData(fileId: Int) async -> Data? {
        guard let file = try? await service.downloadFile(
            fileId: fileId,
            limit: 0,
            offset: 0,
            priority: 1,
            synchronous: true,
        ), file.local.isDownloadingCompleted, !file.local.path.isEmpty else { return nil }
        return try? Data(contentsOf: URL(filePath: file.local.path))
    }

    @MainActor private func loadPickedPhoto(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self) else { return }
        pendingPhotoData = data
    }

    @MainActor private func save() async {
        guard let loaded, canSave else { return }

        // Catch obviously malformed usernames before the round-trip, mirroring Telegram-iOS's
        // local `_internal_checkAddressNameFormat`. TDLib has no personal-username availability
        // check (`checkChatUsername` is chats-only), so everything else is mapped from the error
        // `setUsername` throws.
        if username != loaded.username, let issue = Self.usernameFormatIssue(username) {
            errorMessage = issue.message
            return
        }

        isSaving = true
        defer { isSaving = false }
        do {
            if let pendingPhotoData {
                let fileURL = FileManager.default
                    .temporaryDirectory
                    .appending(path: "\(UUID().uuidString).jpeg")
                try pendingPhotoData.write(to: fileURL)
                defer { try? FileManager.default.removeItem(at: fileURL) }
                _ = try await service.setProfilePhoto(
                    isPublic: true,
                    photo: .inputChatPhotoStatic(.init(photo: .inputFileLocal(.init(path: fileURL.path)))),
                )
            }
            if firstName != loaded.firstName || lastName != loaded.lastName {
                _ = try await service.setName(firstName: firstName, lastName: lastName)
            }
            if bio != loaded.bio {
                _ = try await service.setBio(bio: bio)
            }
            if username != loaded.username {
                do {
                    _ = try await service.setUsername(username: username)
                } catch let error as TDLibKit.Error
                    where error.message.trimmingCharacters(in: .whitespacesAndNewlines) == "USERNAME_PURCHASE_AVAILABLE"
                {
                    // The username is already taken but listed for auction on Fragment. Any
                    // name/bio/photo edits above already went through, so reflect those and keep
                    // the sheet open with the Fragment offer rather than a cryptic raw error.
                    if let pendingPhotoData {
                        photoData = pendingPhotoData
                    }
                    pendingPhotoData = nil
                    self.loaded = LoadedProfile(
                        firstName: firstName,
                        lastName: lastName,
                        bio: bio,
                        username: loaded.username,
                    )
                    fragmentUsernameOffer = username
                    return
                }
            }
            if let pendingPhotoData {
                photoData = pendingPhotoData
            }
            pendingPhotoData = nil
            self.loaded = LoadedProfile(firstName: firstName, lastName: lastName, bio: bio, username: username)
            dismiss()
        } catch {
            errorMessage = Self.editProfileErrorMessage(error)
        }
    }
}

// MARK: - UsernameFormatIssue

private enum UsernameFormatIssue {
    case tooShort
    case startsWithNumber
    case startsWithUnderscore
    case endsWithUnderscore
    case invalidCharacters

    // MARK: Internal

    var message: String {
        switch self {
        case .tooShort:
            "Usernames need to be at least 5 characters long."
        case .startsWithNumber:
            "Usernames can't start with a number."
        case .startsWithUnderscore:
            "Usernames can't start with an underscore."
        case .endsWithUnderscore:
            "Usernames can't end with an underscore."
        case .invalidCharacters:
            "Usernames can only use letters, numbers and underscores."
        }
    }
}

// MARK: - LoadedProfile

private struct LoadedProfile: Equatable {
    let firstName: String
    let lastName: String
    let bio: String
    let username: String
}

// MARK: - Image + profile photo decoding

private extension Image {
    /// The only platform branch in this file - a pixel decoder, not picker/UI logic. Kept local
    /// rather than touching `BetterTG/Extensions/Image+.swift`, which hard-codes `UIImage` and is
    /// iOS-only.
    init?(profilePhotoData data: Data) {
        #if os(iOS)
        guard let uiImage = UIImage(data: data) else { return nil }
        self.init(uiImage: uiImage)
        #else
        guard let nsImage = NSImage(data: data) else { return nil }
        self.init(nsImage: nsImage)
        #endif
    }
}
