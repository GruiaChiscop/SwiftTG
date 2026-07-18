// ServiceSoundManager.swift

import AudioToolbox
import UIKit

@MainActor final class ServiceSoundManager {
    // MARK: Lifecycle

    private init() {
        self.messageDeliveredSound = loadSound(
            named: TelegramServiceSoundPolicy.deliveredResourceName,
            extension: TelegramServiceSoundPolicy.resourceExtension,
        )
        self.incomingMessageSound = loadSound(
            named: TelegramServiceSoundPolicy.incomingResourceName,
            extension: TelegramServiceSoundPolicy.resourceExtension,
        )
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
        guard policy.shouldPlayDelivered() else { return }
        play(messageDeliveredSound)
    }

    func playIncomingMessageIfAppropriate(isMuted: Bool) {
        guard policy.shouldPlayIncoming(
            applicationIsActive: UIApplication.shared.applicationState == .active,
            isMuted: isMuted,
        ) else { return }
        play(incomingMessageSound)
    }

    // MARK: Private

    private var incomingMessageSound: SystemSoundID = 0
    private var messageDeliveredSound: SystemSoundID = 0
    private var policy = TelegramServiceSoundPolicy()

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
