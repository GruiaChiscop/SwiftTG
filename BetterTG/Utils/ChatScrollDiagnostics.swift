// ChatScrollDiagnostics.swift

import Foundation

/// Records a chat-history scroll decision to `ChatScrollDiagnostics` (DEBUG builds only, a no-op
/// in Release) - callable unconditionally, same pattern as `voicePlaybackTrace`.
@MainActor func chatScrollTrace(_ message: @autoclosure () -> String) {
    #if DEBUG
    ChatScrollDiagnostics.shared.record(message())
    #endif
}

#if DEBUG
import UIKit

// MARK: - ChatScrollDiagnostics

/// A DEBUG-only, in-memory trace of chat-history scroll decisions and VoiceOver focus moves, so a
/// live "VoiceOver jumps around unpredictably" repro can be turned into an actual timeline instead
/// of another guess. Records nothing in Release builds.
///
/// Reachable in the app as You tab > Developer > Chat Scroll Log, which shows this trace and lets
/// it be copied to send along with a repro.
@MainActor final class ChatScrollDiagnostics {
    // MARK: Lifecycle

    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(elementFocused(_:)),
            name: UIAccessibility.elementFocusedNotification,
            object: nil,
        )
    }

    // MARK: Internal

    static let shared = ChatScrollDiagnostics()

    private(set) var entries = [String]()

    var exportedText: String {
        entries.isEmpty ? "(empty)" : entries.joined(separator: "\n")
    }

    func record(_ message: String) {
        let voiceOver = UIAccessibility.isVoiceOverRunning ? "VO=on" : "VO=off"
        append("\(timestamp()) [\(voiceOver)] \(message)")
    }

    func clear() {
        entries.removeAll()
    }

    // MARK: Private

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    private func timestamp() -> String {
        Self.formatter.string(from: .now)
    }

    private func append(_ line: String) {
        entries.append(line)
        if entries.count > 500 {
            entries.removeFirst(entries.count - 500)
        }
    }

    @objc private func elementFocused(_ notification: Notification) {
        let element = notification.userInfo?[UIAccessibility.focusedElementUserInfoKey]
        let label = (element as? NSObject)?.accessibilityLabel ?? "?"
        let snippet = label.prefix(60)
        record("VoiceOver focused: \"\(snippet)\(label.count > 60 ? "…" : "")\"")
    }
}
#endif
