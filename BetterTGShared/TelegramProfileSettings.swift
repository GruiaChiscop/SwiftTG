// TelegramProfileSettings.swift

import PhotosUI
import SwiftUI
import TDLibKit

#if os(iOS)
import UIKit
#else
import AppKit
#endif

// MARK: - EditProfileView

struct EditProfileView: View {
    // MARK: Lifecycle

    init(service: any TelegramService, showsCancelButton: Bool = false) {
        self.service = service
        self.showsCancelButton = showsCancelButton
    }

    // MARK: Internal

    var body: some View {
        NavigationStack {
            form
                .navigationTitle("Edit Profile")
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
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss

    @State private var bio = ""
    @State private var errorMessage: String?
    @State private var firstName = ""
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
            Section {
                photoSection
                TextField("First name", text: $firstName)
                TextField("Last name", text: $lastName)
            } footer: {
                Text("Enter your name and add an optional profile photo.")
            }

            Section {
                TextField("Bio", text: $bio, axis: .vertical)
            } header: {
                Text("Bio")
            } footer: {
                Text("Any details such as age, occupation or city.\nExample: 23 y.o. designer from San Francisco.")
            }

            Section {
                TextField("Username", text: $username)
            } header: {
                Text("Username")
            } footer: {
                // Matches Telegram-iOS's Username.Help string verbatim (en.lproj/Localizable.strings).
                Text(
                    "You can choose a username on **Telegram**. If you do, other people will be able to find you by this username and contact you without knowing your phone number.\n\nYou can use **a-z**, **0-9** and underscores. Minimum length is **5** characters.",
                )
            }

            if isSaving {
                Section {
                    ProgressView("Saving…")
                }
            }
        }
    }

    private var photoSection: some View {
        HStack {
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
                    Text(photoData == nil && pendingPhotoData == nil ? "Add Photo" : "Change Photo")
                }
            }
            Spacer()
        }
        .padding(.vertical, 8)
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
                _ = try await service.setUsername(username: username)
            }
            if let pendingPhotoData {
                photoData = pendingPhotoData
            }
            pendingPhotoData = nil
            self.loaded = LoadedProfile(firstName: firstName, lastName: lastName, bio: bio, username: username)
            dismiss()
        } catch {
            errorMessage = telegramErrorDescription(error)
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
