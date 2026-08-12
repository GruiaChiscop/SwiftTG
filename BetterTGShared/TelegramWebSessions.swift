// TelegramWebSessions.swift

import SwiftUI
@preconcurrency import TDLibKit

// MARK: - TelegramWebSessionsView

struct TelegramWebSessionsView: View {
    // MARK: Lifecycle

    init(service: any TelegramService, onCountChanged: @escaping (Int) -> Void = { _ in }) {
        self.service = service
        self.onCountChanged = onCountChanged
    }

    // MARK: Internal

    var body: some View {
        Group {
            if isLoading, websites.isEmpty {
                ProgressView("Loading Web Sessions…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if websites.isEmpty {
                ContentUnavailableView(
                    "No Web Sessions",
                    systemImage: "globe",
                    description: Text("Websites where you sign in with Telegram will appear here."),
                )
            } else {
                List {
                    Section {
                        ForEach(websites) { website in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(website.domainName)
                                    .font(.headline)
                                Text([website.browser, website.platform]
                                    .filter { !$0.isEmpty }
                                    .joined(separator: " · "))
                                    .foregroundStyle(.secondary)
                                Text("Last active \(lastActiveText(for: website))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if !website.location.isEmpty || !website.ipAddress.isEmpty {
                                    Text([website.location, website.ipAddress]
                                        .filter { !$0.isEmpty }
                                        .joined(separator: " · "))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Button("Disconnect", role: .destructive) {
                                    Task { await disconnect(website) }
                                }
                                .disabled(disconnectingWebsiteIds.contains(website.id))
                            }
                            .padding(.vertical, 4)
                        }
                    }

                    Section {
                        Button("Disconnect All Web Sessions", role: .destructive) {
                            confirmsDisconnectAll = true
                        }
                        .disabled(isDisconnectingAll)
                    }
                }
            }
        }
        .navigationTitle("Web Sessions")
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            await loadWebsites()
        }
        .confirmationDialog(
            "Disconnect all websites?",
            isPresented: $confirmsDisconnectAll,
            titleVisibility: .visible,
        ) {
            Button("Disconnect All", role: .destructive) {
                Task { await disconnectAll() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You will need to sign in again on every connected website.")
        }
        .alert("Web Sessions Error", isPresented: errorIsPresented) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Private

    @State private var confirmsDisconnectAll = false
    @State private var disconnectingWebsiteIds = Set<TdInt64>()
    @State private var errorMessage: String?
    @State private var hasLoaded = false
    @State private var isDisconnectingAll = false
    @State private var isLoading = false
    @State private var websites = [ConnectedWebsite]()

    private let onCountChanged: (Int) -> Void
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

    private func lastActiveText(for website: ConnectedWebsite) -> String {
        Date(timeIntervalSince1970: TimeInterval(website.lastActiveDate))
            .formatted(date: .abbreviated, time: .shortened)
    }

    @MainActor private func loadWebsites() async {
        isLoading = true
        defer { isLoading = false }
        do {
            websites = try await service.getConnectedWebsites()
                .websites
                .sorted { $0.lastActiveDate > $1.lastActiveDate }
            onCountChanged(websites.count)
        } catch {
            errorMessage = telegramErrorDescription(error)
        }
    }

    @MainActor private func disconnect(_ website: ConnectedWebsite) async {
        disconnectingWebsiteIds.insert(website.id)
        defer { disconnectingWebsiteIds.remove(website.id) }
        do {
            _ = try await service.disconnectWebsite(websiteId: website.id)
            websites.removeAll { $0.id == website.id }
            onCountChanged(websites.count)
        } catch {
            errorMessage = telegramErrorDescription(error)
        }
    }

    @MainActor private func disconnectAll() async {
        isDisconnectingAll = true
        defer { isDisconnectingAll = false }
        do {
            _ = try await service.disconnectAllWebsites()
            websites = []
            onCountChanged(0)
        } catch {
            errorMessage = telegramErrorDescription(error)
        }
    }
}
