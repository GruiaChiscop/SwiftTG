// TelegramAppLock.swift

import Foundation
import LocalAuthentication
import Observation
import SwiftUI

// MARK: - TelegramAppLockDelay

enum TelegramAppLockDelay: Int, CaseIterable, Identifiable {
    case immediately = 0
    case oneMinute = 60
    case fiveMinutes = 300
    case oneHour = 3600

    // MARK: Internal

    static let defaultsKey = "BetterTG.appLock.delaySeconds"

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .immediately: "Immediately"
        case .oneMinute: "After 1 Minute"
        case .fiveMinutes: "After 5 Minutes"
        case .oneHour: "After 1 Hour"
        }
    }

    var seconds: TimeInterval { TimeInterval(rawValue) }

    static func stored() -> Self {
        Self(rawValue: UserDefaults.standard.integer(forKey: defaultsKey)) ?? .immediately
    }
}

// MARK: - TelegramAppLockController

/// Deliberately holds no secret of its own - unlike Telegram-iOS's own passcode (which is always
/// required, with biometrics layered on top only as a shortcut), this gates the app entirely
/// through `LAContext`'s `.deviceOwnerAuthentication` policy: Face ID/Touch ID first, falling
/// back to the device's own passcode automatically if biometrics fail or aren't available. No
/// app-specific code is ever stored - the user's device lock is the whole mechanism.
@MainActor
@Observable final class TelegramAppLockController {
    // MARK: Lifecycle

    private init() {}

    // MARK: Internal

    static let shared = TelegramAppLockController()

    private(set) var isLocked = false

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.enabledDefaultsKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.enabledDefaultsKey)
            if !newValue {
                isLocked = false
            }
        }
    }

    var canUseDeviceAuthentication: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    var biometryType: LABiometryType {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
        return context.biometryType
    }

    /// Call when the app is about to leave the foreground.
    func noteDidEnterBackground() {
        guard isEnabled else { return }
        backgroundedAt = Date()
    }

    /// Call when the app is about to return to the foreground. Locks immediately if the
    /// configured auto-lock delay has elapsed since backgrounding.
    func noteWillEnterForeground() {
        defer { backgroundedAt = nil }
        guard isEnabled, let backgroundedAt else { return }
        if Date().timeIntervalSince(backgroundedAt) >= TelegramAppLockDelay.stored().seconds {
            isLocked = true
        }
    }

    @discardableResult func authenticate() async -> Bool {
        guard !isAuthenticating else { return false }
        isAuthenticating = true
        defer { isAuthenticating = false }
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else { return false }
        let success = await (try? context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: "Unlock SwiftTG",
        )) ?? false
        if success {
            isLocked = false
        }
        return success
    }

    // MARK: Private

    private static let enabledDefaultsKey = "BetterTG.appLock.enabled"

    private var backgroundedAt: Date?
    private var isAuthenticating = false
}

extension LABiometryType {
    var displayName: String? {
        switch self {
        case .faceID: "Face ID"
        case .touchID: "Touch ID"
        case .opticID: "Optic ID"
        case .none: nil
        @unknown default: nil
        }
    }
}

// MARK: - TelegramAppLockOverlay

/// Full-screen overlay shown whenever the app lock is engaged. Attach with `.appLockOverlay()`
/// at the root of each platform's window content.
struct TelegramAppLockOverlay: ViewModifier {
    @Bindable var controller: TelegramAppLockController

    func body(content: Content) -> some View {
        content.overlay {
            if controller.isLocked {
                TelegramAppLockView(controller: controller)
                    .transition(.opacity)
            }
        }
    }
}

extension View {
    func appLockOverlay(controller: TelegramAppLockController = .shared) -> some View {
        modifier(TelegramAppLockOverlay(controller: controller))
    }
}

// MARK: - TelegramAppLockView

struct TelegramAppLockView: View {
    // MARK: Internal

    @Bindable var controller: TelegramAppLockController

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: lockIconName)
                .font(.system(size: 44))
                .foregroundStyle(.secondary)

            Text("SwiftTG Locked")
                .font(.title2.bold())

            if let biometryName = controller.biometryType.displayName {
                Text("Use \(biometryName) or your device passcode to continue.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Button("Unlock") {
                Task { await controller.authenticate() }
            }
            .buttonStyle(.borderedProminent)

            Spacer()
            Spacer()
        }
        .padding()
        .background(.background)
        .task {
            _ = await controller.authenticate()
        }
    }

    // MARK: Private

    private var lockIconName: String {
        switch controller.biometryType {
        case .faceID: "faceid"
        case .touchID: "touchid"
        default: "lock.fill"
        }
    }
}

// MARK: - TelegramAppLockSettingsView

struct TelegramAppLockSettingsView: View {
    // MARK: Internal

    var body: some View {
        Form {
            Section {
                Toggle("Require \(unlockMethodName)", isOn: Binding(
                    get: { controller.isEnabled },
                    set: { controller.isEnabled = $0 },
                ))
                .disabled(!controller.canUseDeviceAuthentication)
            } footer: {
                if !controller.canUseDeviceAuthentication {
                    Text("Set a passcode for this device to use this feature.")
                } else {
                    Text(
                        "SwiftTG will ask for \(unlockMethodName) after being in the background for a while. No separate passcode is stored by the app - your device's own lock is used.",
                    )
                }
            }

            if controller.isEnabled {
                Section {
                    Picker("Auto-Lock", selection: $autoLockDelay) {
                        ForEach(TelegramAppLockDelay.allCases) { delay in
                            Text(delay.title).tag(delay.rawValue)
                        }
                    }
                }
            }
        }
        .navigationTitle("App Lock")
        .onChange(of: autoLockDelay) { _, newValue in
            UserDefaults.standard.set(newValue, forKey: TelegramAppLockDelay.defaultsKey)
        }
    }

    // MARK: Private

    @State private var autoLockDelay = TelegramAppLockDelay.stored().rawValue
    @State private var controller = TelegramAppLockController.shared

    private var unlockMethodName: String {
        controller.biometryType.displayName ?? "Device Passcode"
    }
}
