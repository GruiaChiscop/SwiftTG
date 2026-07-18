// MacServiceSoundManager.swift

import AppKit

@MainActor final class MacServiceSoundManager {
    // MARK: Lifecycle

    private init() {
        self.messageDeliveredSound = Self.loadSound(
            named: TelegramServiceSoundPolicy.deliveredResourceName,
            extension: TelegramServiceSoundPolicy.resourceExtension,
        )
        self.incomingMessageSound = Self.loadSound(
            named: TelegramServiceSoundPolicy.incomingResourceName,
            extension: TelegramServiceSoundPolicy.resourceExtension,
        )
    }

    // MARK: Internal

    static let shared = MacServiceSoundManager()

    func playMessageDelivered() {
        guard policy.shouldPlayDelivered() else { return }
        play(messageDeliveredSound)
    }

    func playIncomingMessageIfAppropriate(isMuted: Bool) {
        guard policy.shouldPlayIncoming(
            applicationIsActive: NSApplication.shared.isActive,
            isMuted: isMuted,
        ) else { return }
        play(incomingMessageSound)
    }

    // MARK: Private

    private let incomingMessageSound: NSSound?
    private let messageDeliveredSound: NSSound?
    private var policy = TelegramServiceSoundPolicy()

    private static func loadSound(named name: String, extension fileExtension: String) -> NSSound? {
        guard let url = Bundle.main.url(forResource: name, withExtension: fileExtension) else { return nil }
        return NSSound(contentsOf: url, byReference: true)
    }

    private func play(_ sound: NSSound?) {
        guard let sound else { return }
        if sound.isPlaying {
            sound.stop()
        }
        sound.play()
    }
}
