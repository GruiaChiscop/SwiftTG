// StableIconButton.swift

import SwiftUI
import UIKit

// MARK: - StableIconButton

/// Same fix as `StableTranslationBannerLabel`, for a tappable icon instead of a label: a native
/// `UIButton` keeps one persistent accessibility element mounted while sibling content (message
/// rows, other banners) reflows, instead of a SwiftUI `Button` that VoiceOver can lose focus on
/// when that happens.
///
/// Root cause (so this doesn't need rediscovering per element): the message `List` is UITableView-
/// backed, and self-sizing rows (images/link previews resolving async) keep nudging it through
/// relayout even in an otherwise idle chat. Each pass makes UIKit post an accessibility layout
/// change, and VoiceOver resets focus off anything nearby that's a plain SwiftUI view without its
/// own stable identity - confirmed so far for icon-only buttons (`.labelStyle(.iconOnly)`) and
/// standalone `Text` not embedded as a button's own visible label. This can't be suppressed from
/// SwiftUI - it's UITableView's own accessibility notifications, not something app code posts.
/// Any new icon-only control placed near the message list (in this VStack, an overlay atop it, or
/// otherwise adjacent - e.g. future call buttons, should they end up here rather than in the
/// navigation toolbar) should use this rather than a plain SwiftUI `Button` + `.labelStyle(.iconOnly)`.
/// Buttons whose visible content already *is* their accessible label (a `Text`-labeled `Button`)
/// have held up fine so far and don't need this.
///
/// TODO: Signal-iOS sidesteps this class of bug entirely rather than working around it - its
/// conversation view is plain UIKit (`UICollectionView` + a custom `UICollectionViewLayout`), and
/// cells are explicitly *not* self-sizing: `CVCell.preferredLayoutAttributesFitting` returns the
/// input unchanged, with row sizes precomputed by its own measurement pipeline
/// (`CVLoadCoordinator`/`CVRenderItem`) instead of discovered via Auto Layout as content resolves.
/// That's the actual root cause difference from our `List` - worth investigating whether the same
/// (precomputed message-row sizing instead of relying on self-sizing) is feasible here, which would
/// remove the need for `StableIconButton`/`StableTranslationBannerLabel` altogether instead of
/// working around it per element. Deferred; not attempted yet.
struct StableIconButton: UIViewRepresentable {
    let systemImageName: String
    let accessibilityLabel: String
    let action: () -> Void

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: systemImageName), for: .normal)
        button.accessibilityLabel = accessibilityLabel
        button.addTarget(context.coordinator, action: #selector(Coordinator.performAction), for: .touchUpInside)
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        context.coordinator.action = action
        if button.accessibilityLabel != accessibilityLabel {
            button.accessibilityLabel = accessibilityLabel
        }
        if context.coordinator.systemImageName != systemImageName {
            context.coordinator.systemImageName = systemImageName
            button.setImage(UIImage(systemName: systemImageName), for: .normal)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action, systemImageName: systemImageName)
    }

    final class Coordinator {
        var action: () -> Void
        var systemImageName: String

        init(action: @escaping () -> Void, systemImageName: String) {
            self.action = action
            self.systemImageName = systemImageName
        }

        @objc func performAction() {
            action()
        }
    }
}
