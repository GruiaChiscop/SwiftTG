// ApplicationIdleTimer.swift

import UIKit

@MainActor enum ApplicationIdleTimer {
    // MARK: Internal

    static func acquire() -> UUID {
        let token = UUID()
        tokens.insert(token)
        updateApplication()
        return token
    }

    static func release(_ token: UUID) {
        tokens.remove(token)
        updateApplication()
    }

    // MARK: Private

    private static var tokens = Set<UUID>()

    private static func updateApplication() {
        UIApplication.shared.isIdleTimerDisabled = !tokens.isEmpty
    }
}
