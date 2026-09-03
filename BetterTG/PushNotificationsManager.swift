// PushNotificationsManager.swift

import UIKit
import UserNotifications

@MainActor final class PushNotificationsManager {
    // MARK: Lifecycle

    private init(service: any TelegramService = TDLib.shared.service) {
        self.registration = TelegramApplePushRegistration(
            service: service,
            isAppSandbox: Self.isAppSandbox,
        )
    }

    // MARK: Internal

    static let shared = PushNotificationsManager()

    func start() {
        registration.start()
    }

    /// Must run on every launch while signed in: iOS only delivers the APNs device token to
    /// `AppDelegate.didRegisterForRemoteNotificationsWithDeviceToken` in response to this call, and
    /// that callback is the only place `TelegramApplePushRegistration` learns the token it hands to
    /// TDLib's `registerDevice`. It never prompts - that's `requestAuthorization()` - so calling it
    /// regardless of authorization status is both safe and required.
    func registerForRemoteNotifications() {
        UIApplication.shared.registerForRemoteNotifications()
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await notificationCenter.notificationSettings().authorizationStatus
    }

    @discardableResult func requestAuthorization() async -> Bool {
        let granted = await (try? notificationCenter.requestAuthorization(
            options: [.alert, .badge, .sound],
        )) == true
        guard granted else { return false }
        UIApplication.shared.registerForRemoteNotifications()
        return true
    }

    func didRegister(deviceToken: Data) {
        registration.didRegister(deviceToken: deviceToken)
    }

    func didFailToRegister(error: any Swift.Error) {
        print("APNs registration failed: \(error.localizedDescription)")
    }

    func process(userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        do {
            try await registration.process(userInfo: userInfo)
            return .newData
        } catch {
            print("TDLib push processing failed: \(error.localizedDescription)")
            return .failed
        }
    }

    // MARK: Private

    private static var isAppSandbox: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    private let notificationCenter = UNUserNotificationCenter.current()
    private let registration: TelegramApplePushRegistration
}
