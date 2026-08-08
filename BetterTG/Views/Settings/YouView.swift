// YouView.swift

import SwiftUI
import TDLibKit

struct YouView: View {
    // MARK: Lifecycle

    init(service: any TelegramService) {
        self.service = service
    }

    // MARK: Internal

    var body: some View {
        List {
            Section {
                if let user {
                    profileHeader(user)
                } else if isLoading {
                    HStack {
                        Spacer()
                        ProgressView("Loading profile…")
                        Spacer()
                    }
                }
            }

            Section("Settings") {
                Button {
                    showsEditProfile = true
                } label: {
                    Label("Edit Profile", systemImage: "person.crop.circle")
                }
                .foregroundStyle(.primary)

                NavigationLink {
                    BlockedUsersView(service: service)
                } label: {
                    Label("Blocked Users", systemImage: "hand.raised.slash")
                }

                NavigationLink {
                    ActiveSessionsView(service: service)
                } label: {
                    Label("Devices", systemImage: "checkmark.shield")
                }

                NavigationLink {
                    TelegramNotificationsView(service: service)
                } label: {
                    Label("Notifications and Sounds", systemImage: "bell")
                }

                NavigationLink {
                    TelegramAppearanceSettingsView()
                } label: {
                    Label("Appearance", systemImage: "paintpalette")
                }

                NavigationLink {
                    TelegramPrivacyView(service: service)
                } label: {
                    Label("Privacy", systemImage: "hand.raised")
                }

                NavigationLink {
                    TelegramTwoStepVerificationView(service: service)
                } label: {
                    Label("Two-Step Verification", systemImage: "lock.shield")
                }

                NavigationLink {
                    TelegramAppLockSettingsView()
                } label: {
                    Label("App Lock", systemImage: "lock")
                }

                NavigationLink {
                    TelegramStorageSettingsView(service: service)
                } label: {
                    Label("Storage Usage", systemImage: "internaldrive")
                }

                NavigationLink {
                    TelegramProxySettingsView(service: service)
                } label: {
                    Label("Proxy", systemImage: "network")
                }

                NavigationLink {
                    TelegramChatFoldersView(service: service)
                } label: {
                    Label("Chat Folders", systemImage: "folder")
                }
            }
        }
        .navigationTitle("You")
        .task { await loadProfile() }
        .refreshable { await loadProfile() }
        .sheet(isPresented: $showsEditProfile, onDismiss: { Task { await loadProfile() } }) {
            EditProfileView(service: service, showsCancelButton: true)
        }
        .alert("Profile couldn't be loaded", isPresented: errorIsPresented) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Private

    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var showsEditProfile = false
    @State private var user: User?

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

    private func profileHeader(_ user: User) -> some View {
        let displayName = telegramUserDisplayName(user)
        return HStack(spacing: 14) {
            ProfileImageView(
                photo: user.profilePhoto?.small,
                minithumbnail: user.profilePhoto?.minithumbnail,
                title: displayName,
                userId: user.id,
                fontSize: 30,
            )
            .frame(width: 72, height: 72)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(displayName)
                    .font(.title2.bold())
                if let username = user.usernames?.activeUsernames.first {
                    Text("@\(username)")
                        .foregroundStyle(.secondary)
                }
                if !user.phoneNumber.isEmpty {
                    Text("+\(user.phoneNumber)")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 8)
    }

    @MainActor private func loadProfile() async {
        isLoading = user == nil
        defer { isLoading = false }
        do {
            user = try await service.getMe()
        } catch {
            errorMessage = telegramErrorDescription(error)
        }
    }
}
