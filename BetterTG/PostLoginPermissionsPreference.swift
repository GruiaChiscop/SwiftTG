// PostLoginPermissionsPreference.swift

import Foundation

enum PostLoginPermissionsPreference {
    // MARK: Internal

    static var hasCompleted: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    // MARK: Private

    private static let key = "PostLoginPermissionsPreference.hasCompleted"
}
