// TelegramInAppNotificationBannerView.swift

import SwiftUI

// MARK: - TelegramInAppNotificationBannerView

/// Replaces the system notification banner while the app is active - see
/// `RootVM.handleNotificationGroupUpdate` for why the system one is suppressed in that state.
struct TelegramInAppNotificationBannerView: View {
    // MARK: Internal

    var body: some View {
        if let banner = rootVM.inAppNotificationBanner {
            content(for: banner)
                .id(banner.id)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onAppear {
                    // `.announcement`, not `.screenChanged` - reads the banner aloud without moving
                    // VoiceOver's focus away from wherever the user actually is.
                    AccessibilityNotification.Announcement("\(banner.title). \(banner.body)").post()
                }
        }
    }

    // MARK: Private

    @Bindable private var rootVM = RootVM.shared

    private func content(for banner: TelegramInAppNotificationBanner) -> some View {
        Button {
            withAnimation { rootVM.openInAppNotification(banner) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(banner.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(banner.body)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background(.bar, in: RoundedRectangle(cornerRadius: 14))
        .shadow(radius: 8, y: 2)
        .padding(.horizontal, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("New message, \(banner.title), \(banner.body)")
        .accessibilityAction(named: "Open Chat") {
            withAnimation { rootVM.openInAppNotification(banner) }
        }
        .accessibilityAction(named: "Dismiss") {
            withAnimation { rootVM.dismissInAppNotification() }
        }
        .gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    guard value.translation.height < 0 else { return }
                    withAnimation { rootVM.dismissInAppNotification() }
                },
        )
    }
}
