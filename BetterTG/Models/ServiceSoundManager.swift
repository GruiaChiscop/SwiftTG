// ServiceSoundManager.swift

import AudioToolbox
import UIKit

@MainActor final class ServiceSoundManager {
    // MARK: Lifecycle

    private init() {
        self.messageDeliveredSound = loadSound(named: "MessageSent", extension: "mp3")
        self.incomingMessageSound = loadSound(named: "notification", extension: "mp3")
    }

    deinit {
        if messageDeliveredSound != 0 {
            AudioServicesDisposeSystemSoundID(messageDeliveredSound)
        }
        if incomingMessageSound != 0 {
            AudioServicesDisposeSystemSoundID(incomingMessageSound)
        }
    }

    // MARK: Internal

    static let shared = ServiceSoundManager()

    func playMessageDelivered() {
        guard Date().timeIntervalSince(lastDeliveredPlayback) > 0.2 else { return }
        lastDeliveredPlayback = Date()
        play(messageDeliveredSound)
    }

    func playIncomingMessageIfAppropriate(isMuted: Bool) {
        guard UIApplication.shared.applicationState == .active, !isMuted else { return }
        guard Date().timeIntervalSince(lastIncomingPlayback) > 0.2 else { return }
        lastIncomingPlayback = Date()
        play(incomingMessageSound)
    }

    // MARK: Private

    private var incomingMessageSound: SystemSoundID = 0
    private var messageDeliveredSound: SystemSoundID = 0
    private var lastIncomingPlayback = Date.distantPast
    private var lastDeliveredPlayback = Date.distantPast

    private func loadSound(named name: String, extension fileExtension: String) -> SystemSoundID {
        guard let url = Bundle.main.url(forResource: name, withExtension: fileExtension) else { return 0 }
        var sound: SystemSoundID = 0
        guard AudioServicesCreateSystemSoundID(url as CFURL, &sound) == noErr else { return 0 }
        return sound
    }

    private func play(_ sound: SystemSoundID) {
        guard sound != 0 else { return }
        AudioServicesPlaySystemSound(sound)
    }
}
