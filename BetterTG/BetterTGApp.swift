// BetterTGApp.swift

import AVKit
import SwiftUI
import TDLibKit
import UserNotifications

// MARK: - BetterTGApp

@main struct BetterTGApp: App {
    // MARK: Lifecycle

    init() {
        guard !Utils.isRunningTests else { return }
        TDLib.shared.startTdLibUpdateHandler()

        #if DEBUG
        if CommandLine.arguments.contains("-mockData") {
            MockData.install()
        }
        #endif

        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
//        UINavigationBar.appearance().compactAppearance = appearance
//        UINavigationBar.appearance().standardAppearance = appearance
//        UINavigationBar.appearance().compactScrollEdgeAppearance = appearance
    }

    // MARK: Internal

    @UIApplicationDelegateAdaptor var delegate: AppDelegate

    var body: some Scene {
        WindowGroup {
            // The test bundle needs BetterTG.app as its host process just to link against the
            // app's own symbols (see `Utils.isRunningTests`) - it never wants the real app to
            // actually run, which would otherwise stand up a live TDLib client via `RootVM.shared`.
            if Utils.isRunningTests {
                EmptyView()
            } else {
                RootView()
            }
        }
    }
}

// MARK: - AppDelegate

@MainActor final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _: UIApplication,
        didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil,
    ) -> Bool {
        guard !Utils.isRunningTests else { return true }
        UNUserNotificationCenter.current().delegate = self
        PushNotificationsManager.shared.start()
        return true
    }

    func application(
        _: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data,
    ) {
        PushNotificationsManager.shared.didRegister(deviceToken: deviceToken)
    }

    func application(
        _: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: any Swift.Error,
    ) {
        PushNotificationsManager.shared.didFailToRegister(error: error)
    }

    func application(
        _: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void,
    ) {
        Task {
            let result = await PushNotificationsManager.shared.process(userInfo: userInfo)
            completionHandler(result)
        }
    }

    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void,
    ) {
        completionHandler([.banner, .list, .sound, .badge])
        let userInfo = notification.request.content.userInfo
        Task { @MainActor in
            _ = await PushNotificationsManager.shared.process(userInfo: userInfo)
        }
    }

    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void,
    ) {
        let content = response.notification.request.content
        var userInfo = content.userInfo
        if !content.threadIdentifier.isEmpty {
            userInfo["thread-id"] = content.threadIdentifier
        }
        Task { @MainActor in
            _ = await PushNotificationsManager.shared.process(userInfo: userInfo)
            if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
                await RootVM.shared.openChatFromNotification(userInfo: userInfo)
            }
            completionHandler()
        }
    }

    func application(
        _: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options _: UIScene.ConnectionOptions,
    ) -> UISceneConfiguration {
        let sceneConfig = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        sceneConfig.delegateClass = SceneDelegate.self
        return sceneConfig
    }
}

// MARK: - SceneDelegate

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(
        _ scene: UIScene,
        willConnectTo _: UISceneSession,
        options _: UIScene.ConnectionOptions,
    ) {
        guard let scene = scene as? UIWindowScene else { return }
        Utils.screen = scene.screen
    }
}
