// RootView.swift

import SwiftUI
import UIKit

struct RootView: View {
    // MARK: Internal

    var body: some View {
        ZStack {
            if rootVM.loggedIn {
                MainView()
                    .safeAreaInset(edge: .top, spacing: 0) {
                        TelegramCallBar()
                    }
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        TelegramLiveLocationBar()
                    }
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        TelegramAudioPlayerBar()
                    }
                    .overlay(alignment: .top) {
                        VStack(spacing: 8) {
                            if let unconfirmedSession = rootVM.unconfirmedSession,
                               RootVM.deviceSessionId(unconfirmedSession) != nil
                            {
                                TelegramUnconfirmedSessionBannerView(
                                    session: unconfirmedSession,
                                    isProcessing: rootVM.isProcessingUnconfirmedSession,
                                    onConfirm: { rootVM.confirmUnconfirmedSession() },
                                    onDeny: { rootVM.denyUnconfirmedSession() },
                                )
                            }
                            TelegramInAppNotificationBannerView()
                        }
                    }
                    .animation(.default, value: rootVM.inAppNotificationBanner)
                    .animation(.default, value: rootVM.unconfirmedSession)

                if !hasCompletedPostLoginPermissions {
                    PostLoginPermissionsView {
                        PostLoginPermissionsPreference.hasCompleted = true
                        withAnimation { hasCompletedPostLoginPermissions = true }
                    }
                    .transition(.opacity)
                }
            } else {
                LoginView()
            }
        }
        .transition(.opacity)
        .overlay {
            if callSession.callRatingSuccessToken != nil {
                CallFeedbackSuccessView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: callSession.callRatingSuccessToken)
        .task(id: callSession.callRatingSuccessToken) {
            await presentCallRatingSuccessIfNeeded()
        }
        .task(id: rootVM.loggedIn) {
            guard rootVM.loggedIn else { return }
            await TelegramKeepMediaPolicy.applyStoredPolicy(service: TDLib.shared.service)
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
            "Join Voice Chat?",
            isPresented: Binding(
                get: { rootVM.pendingGroupCallJoin != nil },
                set: { isPresented in
                    if !isPresented {
                        rootVM.pendingGroupCallJoin = nil
                    }
                },
            ),
            presenting: rootVM.pendingGroupCallJoin,
        ) { _ in
            Button("Join", action: rootVM.confirmPendingGroupCallJoin)
            Button("Cancel", role: .cancel) { rootVM.pendingGroupCallJoin = nil }
        } message: { pending in
            Text(
                pending.totalCount == 1
                    ? "1 participant is in this voice chat. You will join with your microphone off."
                    :
                    "\(pending.totalCount) participants are in this voice chat. You will join with your microphone off.",
            )
        }
        .alert(
            rootVM.pendingVideoChatJoin?.isLiveStream == true ? "Join Live Stream?" : "Join Voice Chat?",
            isPresented: Binding(
                get: { rootVM.pendingVideoChatJoin != nil },
                set: { isPresented in
                    if !isPresented {
                        rootVM.pendingVideoChatJoin = nil
                    }
                },
            ),
            presenting: rootVM.pendingVideoChatJoin,
        ) { pending in
            Button(pending.isLiveStream ? "Watch" : "Join", action: rootVM.confirmPendingVideoChatJoin)
            Button("Cancel", role: .cancel) { rootVM.pendingVideoChatJoin = nil }
        } message: { pending in
            Text(
                pending.isLiveStream
                    ? "Watch the live stream from \(pending.title)."
                    : "Join \(pending.title) with your microphone off.",
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
        .alert(
            "Couldn't Complete Request",
            isPresented: Binding(
                get: { rootVM.unconfirmedSessionActionError != nil },
                set: { isPresented in
                    if !isPresented {
                        rootVM.unconfirmedSessionActionError = nil
                    }
                },
            ),
        ) {
            Button("OK") {}
        } message: {
            Text(rootVM.unconfirmedSessionActionError ?? "")
        }
        .alert(
            "Login Denied",
            isPresented: Binding(
                get: { rootVM.showsDeniedSessionNotice },
                set: { rootVM.showsDeniedSessionNotice = $0 },
            ),
        ) {
            Button("OK") {}
        } message: {
            Text(
                "The session was terminated. If this wasn't you, consider changing your password in Two-Step Verification.",
            )
        }
        .fullScreenCover(isPresented: Binding(
            get: { callSession.shouldShowCallView },
            set: { isPresented in
                if isPresented {
                    callSession.restoreCallView()
                }
            },
        )) {
            CallView()
        }
        .sheet(item: $callSession.pendingCallRating, content: CallRatingView.init)
    }

    // MARK: Private

    @State private var rootVM = RootVM.shared
    @State private var callSession = TelegramCallSession.shared
    @State private var hasCompletedPostLoginPermissions = PostLoginPermissionsPreference.hasCompleted

    private func presentCallRatingSuccessIfNeeded() async {
        guard let token = callSession.callRatingSuccessToken else { return }
        do {
            try await Task.sleep(for: .milliseconds(300))
        } catch {
            return
        }
        guard callSession.callRatingSuccessToken == token else { return }
        UIAccessibility.post(notification: .announcement, argument: "Thanks for your feedback")
        do {
            try await Task.sleep(for: .seconds(2))
        } catch {
            return
        }
        callSession.dismissCallRatingSuccess(token: token)
    }
}
