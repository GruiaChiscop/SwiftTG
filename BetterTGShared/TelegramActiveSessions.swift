// TelegramActiveSessions.swift

import SwiftUI
import TDLibKit

// MARK: - SessionDeviceType + systemImage

extension SessionDeviceType {
    var systemImage: String {
        switch self {
        case .sessionDeviceTypeIphone: "iphone"
        case .sessionDeviceTypeIpad: "ipad"
        case .sessionDeviceTypeAndroid: "candybarphone"
        case .sessionDeviceTypeApple, .sessionDeviceTypeMac: "desktopcomputer"
        case .sessionDeviceTypeLinux, .sessionDeviceTypeUbuntu, .sessionDeviceTypeWindows: "pc"
        case .sessionDeviceTypeBrave, .sessionDeviceTypeChrome, .sessionDeviceTypeEdge,
             .sessionDeviceTypeFirefox, .sessionDeviceTypeOpera, .sessionDeviceTypeSafari,
             .sessionDeviceTypeVivaldi: "globe"
        case .sessionDeviceTypeXbox: "gamecontroller"
        case .sessionDeviceTypeUnknown: "questionmark.circle"
        }
    }
}

/// `telegramErrorDescription` collapses every TDLib code-406 error to the same generic sentence,
/// which for session termination specifically is almost always Telegram's own 24-hour grace period
/// on a freshly-authorized session (confirmed live: `[406] FRESH_RESET_AUTHORISATION_FORBIDDEN`) -
/// not a bug, and not something Telegram-iOS itself has bespoke copy for either (no match anywhere
/// in its `Localizable.strings`), so this is a plain factual explanation rather than invented
/// "official" wording.
private func sessionActionErrorDescription(_ error: Swift.Error) -> String {
    if let tdError = error as? TDLibKit.Error, tdError.message == "FRESH_RESET_AUTHORISATION_FORBIDDEN" {
        return "You can't terminate other sessions within 24 hours of signing in on this device. Try again later."
    }
    return telegramErrorDescription(error)
}

/// Matches Telegram-iOS's session row: "online" for the current session, otherwise a relative
/// last-active time (`ItemListRecentSessionItem.swift`'s `stringForRelativeActivityTimestamp`).
func telegramSessionActivityDescription(_ session: Session) -> String {
    guard !session.isCurrent else { return "Online" }
    let date = Date(timeIntervalSince1970: TimeInterval(session.lastActiveDate))
    return date.formatted(.relative(presentation: .named))
}

// MARK: - ActiveSessionsView

struct ActiveSessionsView: View {
    // MARK: Lifecycle

    init(service: any TelegramService) {
        self.service = service
    }

    // MARK: Internal

    var body: some View {
        List {
            if let currentSession {
                Section("Current Session") {
                    sessionRow(currentSession, showsTerminateButton: false)
                }

                if !otherSessions.isEmpty {
                    Section {
                        Button("Terminate all other sessions", role: .destructive) {
                            confirmsTerminateAll = true
                        }
                        .disabled(isTerminatingAll)
                    } footer: {
                        Text("Logs out all devices except for this one.")
                    }
                }
            }

            if !otherSessions.isEmpty {
                Section("Active Sessions") {
                    ForEach(otherSessions) { session in
                        sessionRow(session, showsTerminateButton: true)
                    }
                }
            } else if !isLoading, currentSession != nil {
                Section {
                    ContentUnavailableView(
                        "No Other Sessions",
                        systemImage: "checkmark.shield",
                        description: Text(
                            "You can log in to Telegram from other mobile, tablet and desktop devices, using the same phone number. All your data will be instantly synchronized.",
                        ),
                    )
                }
            }
        }
        .navigationTitle("Active Sessions")
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            await loadSessions()
        }
        .refreshable { await loadSessions() }
        .alert("Terminate All Other Sessions", isPresented: $confirmsTerminateAll) {
            Button("Terminate All Other Sessions", role: .destructive) {
                Task { await terminateAllOtherSessions() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to terminate all other sessions?")
        }
        .alert("Terminate Session", isPresented: terminationConfirmationIsPresented) {
            Button("Terminate Session", role: .destructive) {
                guard let sessionPendingTermination else { return }
                Task { await terminate(sessionPendingTermination) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to terminate this session?")
        }
        .alert("Error", isPresented: errorIsPresented) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Private

    @State private var confirmsTerminateAll = false
    @State private var errorMessage: String?
    @State private var hasLoaded = false
    @State private var isLoading = false
    @State private var isTerminatingAll = false
    @State private var sessionPendingTermination: Session?
    @State private var sessions = [Session]()
    @State private var terminatingSessionIds = Set<TdInt64>()

    private let service: any TelegramService

    private var currentSession: Session? {
        sessions.first { $0.isCurrent }
    }

    private var otherSessions: [Session] {
        sessions.filter { !$0.isCurrent }
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

    private var terminationConfirmationIsPresented: Binding<Bool> {
        Binding(
            get: { sessionPendingTermination != nil },
            set: { isPresented in
                if !isPresented {
                    sessionPendingTermination = nil
                }
            },
        )
    }

    private func sessionRow(_ session: Session, showsTerminateButton: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: session.deviceType.systemImage)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.deviceModel.isEmpty ? session.platform : session.deviceModel)
                    .font(.body)
                Text("\(session.applicationName) \(session.applicationVersion)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("\(session.location) • \(telegramSessionActivityDescription(session))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)

            if showsTerminateButton {
                Spacer()
                Button(role: .destructive) {
                    sessionPendingTermination = session
                } label: {
                    Label("Terminate session", systemImage: "xmark.circle.fill")
                        .labelStyle(.iconOnly)
                }
                .disabled(terminatingSessionIds.contains(session.id))
            }
        }
    }

    @MainActor private func loadSessions() async {
        isLoading = true
        defer { isLoading = false }
        do {
            sessions = try await service.getActiveSessions().sessions
        } catch {
            errorMessage = sessionActionErrorDescription(error)
        }
    }

    @MainActor private func terminate(_ session: Session) async {
        terminatingSessionIds.insert(session.id)
        defer { terminatingSessionIds.remove(session.id) }
        do {
            _ = try await service.terminateSession(sessionId: session.id)
            sessions.removeAll { $0.id == session.id }
        } catch {
            errorMessage = sessionActionErrorDescription(error)
        }
    }

    @MainActor private func terminateAllOtherSessions() async {
        isTerminatingAll = true
        defer { isTerminatingAll = false }
        do {
            _ = try await service.terminateAllOtherSessions()
            sessions.removeAll { !$0.isCurrent }
        } catch {
            errorMessage = sessionActionErrorDescription(error)
        }
    }
}
