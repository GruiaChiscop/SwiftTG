// Logger.swift

import os.log
import SwiftUI
#if os(iOS)
import UIKit
#endif

let logger = os.Logger(subsystem: "BetterTG", category: "BetterTG")
let dateFormatter: DateFormatter = {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "HH:mm:ss"
    return dateFormatter
}()

func log(_ messages: Any...) {
    let date = dateFormatter.string(from: .now)
    let output = messages.map { "\($0)" }.joined(separator: "\n")
    logger.log("[Log] [\(date, privacy: .public)] \(output, privacy: .public)")
}

func voicePlaybackTrace(_ message: String) {
    #if DEBUG
    print("[VoicePlayback] \(message)")
    logger.debug("[VoicePlayback] \(message, privacy: .public)")
    #endif
}

#if os(iOS)
@MainActor func voiceOverFocusTrace(_ event: String) {
    guard UIAccessibility.isVoiceOverRunning else {
        voicePlaybackTrace("\(event) focus=VoiceOverOff")
        return
    }
    let focusedElement = UIAccessibility.focusedElement(using: .notificationVoiceOver)
    let typeName = focusedElement.map { String(describing: type(of: $0)) } ?? "nil"
    let label: String? =
 if let view = focusedElement as? UIView {
        view.accessibilityLabel
    } else if let element = focusedElement as? UIAccessibilityElement {
        element.accessibilityLabel
    } else {
        nil
    }
    voicePlaybackTrace("\(event) focusType=\(typeName) label=\(label ?? "nil")")
}
#endif
