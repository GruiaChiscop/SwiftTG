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

            Section {
                Button {
                    showsEditProfile = true
                } label: {
                    Label("Edit Profile", systemImage: "person.crop.circle")
                }
                .foregroundStyle(.primary)
            }

            if let proxyStatus = proxyStatusStore.shortcutStatus {
                Section {
                    NavigationLink {
                        TelegramProxySettingsView(service: service)
                    } label: {
                        LabeledContent {
                            Text(proxyStatus.value)
                        } label: {
                            Label("Proxy", systemImage: "network")
                        }
                    }
                }
            }

            Section {
                NavigationLink {
                    ActiveSessionsView(service: service)
                } label: {
                    Label("Devices", systemImage: "checkmark.shield")
                }

                NavigationLink {
                    TelegramChatFoldersView(service: service)
                } label: {
                    Label("Chat Folders", systemImage: "folder")
                }
            }

            Section {
                NavigationLink {
                    TelegramNotificationsView(service: service)
                } label: {
                    Label("Notifications and Sounds", systemImage: "bell")
                }

                NavigationLink {
                    TelegramPrivacyView(service: service)
                } label: {
                    Label("Privacy and Security", systemImage: "hand.raised")
                }

                NavigationLink {
                    TelegramStorageSettingsView(service: service)
                } label: {
                    Label("Data and Storage", systemImage: "internaldrive")
                }

                NavigationLink {
                    TelegramAppearanceSettingsView()
                } label: {
                    Label("Appearance", systemImage: "paintpalette")
                }
            }

            Section {
                Button("Log Out", role: .destructive) {
                    showsLogoutConfirmation = true
                }
                .disabled(isLoggingOut)
            }

            #if DEBUG
            Section("Developer") {
                NavigationLink {
                    ConferenceLabView()
                } label: {
                    Label("Conference Lab", systemImage: "person.3")
                }
            }
            #endif
        }
        .navigationTitle("You")
        .task {
            await loadProfile()
            await proxyStatusStore.refresh(service: service)
        }
        .refreshable {
            await loadProfile()
            await proxyStatusStore.refresh(service: service)
        }
        .sheet(isPresented: $showsEditProfile, onDismiss: { Task { await loadProfile() } }) {
            EditProfileView(service: service, showsCancelButton: true)
        }
        .alert("Profile couldn't be loaded", isPresented: errorIsPresented) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
        .alert("Log Out?", isPresented: $showsLogoutConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Log Out", role: .destructive) { logOut() }
        } message: {
            Text(
                "You'll need to sign in again with your phone number, and this device's local copy of your chats will be cleared.",
            )
        }
    }

    // MARK: Private

    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var isLoggingOut = false
    @State private var showsEditProfile = false
    @State private var showsLogoutConfirmation = false
    @State private var user: User?

    private let service: any TelegramService
    private let proxyStatusStore = TelegramProxyStatusStore.shared

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

    @MainActor private func logOut() {
        guard !isLoggingOut else { return }
        isLoggingOut = true
        Task {
            defer { isLoggingOut = false }
            do {
                // On success TDLib returns to the phone-number state and `RootView` swaps to the
                // login screen on its own.
                _ = try await service.logOut()
            } catch {
                errorMessage = telegramErrorDescription(error)
            }
        }
    }
}
