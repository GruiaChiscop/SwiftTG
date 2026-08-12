// RootView.swift

import SwiftUI

struct RootView: View {
    // MARK: Internal

    var body: some View {
        ZStack {
            if rootVM.loggedIn {
                MainView()
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        TelegramLiveLocationBar()
                    }
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        TelegramAudioPlayerBar()
                    }
                    .overlay(alignment: .top) {
                        TelegramInAppNotificationBannerView()
                    }
                    .animation(.default, value: rootVM.inAppNotificationBanner)
            } else {
                LoginView()
            }
        }
        .transition(.opacity)
        .task(id: rootVM.loggedIn) {
            guard rootVM.loggedIn else { return }
            await TelegramKeepMediaPolicy.applyStoredPolicy(service: TDLib.shared.service)
            await PushNotificationsManager.shared.requestAuthorization()
            await PermissionsManager.shared.requestPostLoginPermissions()
        }
        // Applies everywhere in the subtree - link taps in message text, chat bios, link
        // previews, etc. - so `t.me`/`telegram.me`/`tg:` links resolve in-app instead of always
        // bouncing to Safari. Anything else keeps the system's own default handling.
        .environment(\.openURL, OpenURLAction { url in
            guard TelegramDeepLink.isTelegramLink(url) else { return .systemAction }
            rootVM.handleDeepLink(url)
            return .handled
        })
        .alert(
            "Join Chat?",
            isPresented: Binding(
                get: { rootVM.pendingDeepLinkJoin != nil },
                set: { isPresented in
                    if !isPresented {
                        rootVM.pendingDeepLinkJoin = nil
                    }
                },
            ),
            presenting: rootVM.pendingDeepLinkJoin,
        ) { _ in
            Button("Join") { rootVM.confirmPendingDeepLinkJoin() }
            Button("Cancel", role: .cancel) { rootVM.pendingDeepLinkJoin = nil }
        } message: { pending in
            Text(
                "\(pending.info.title) · \(pending.info.memberCount) member\(pending.info.memberCount == 1 ? "" : "s")",
            )
        }
        .alert(
            "Link Error",
            isPresented: Binding(
                get: { rootVM.deepLinkErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        rootVM.deepLinkErrorMessage = nil
                    }
                },
            ),
        ) {
            Button("OK") {}
        } message: {
            Text(rootVM.deepLinkErrorMessage ?? "")
        }
    }

    // MARK: Private

    @State private var rootVM = RootVM.shared
}
