// ConferenceAccessibilityAnnouncer.swift

import TDLibKit
import UIKit

// MARK: - ConferenceAccessibilityAnnouncer

/// Serializes VoiceOver announcements for live conference participant changes. Initial participant
/// loading is deliberately ignored so joining an existing call doesn't read the entire roster.
@MainActor final class ConferenceAccessibilityAnnouncer {
    // MARK: Lifecycle

    init(service: any TelegramService) {
        self.service = service
    }

    // MARK: Internal

    func enableAfterInitialSnapshot() {
        reset()
        let generation = generation
        activationTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                return
            }
            guard let self, self.generation == generation else { return }
            isEnabled = true
            activationTask = nil
        }
    }

    func reset() {
        generation = UUID()
        isEnabled = false
        activationTask?.cancel()
        activationTask = nil
        announcementTask?.cancel()
        announcementTask = nil
        pendingAnnouncements.removeAll(keepingCapacity: false)
    }

    func participantChanged(
        previous: GroupCallParticipant?,
        current: GroupCallParticipant?,
    ) {
        guard isEnabled,
              UIAccessibility.isVoiceOverRunning,
              let participant = current ?? previous,
              !participant.isCurrentUser
        else { return }

        if previous == nil, current != nil {
            enqueue(participant.participantId, phrase: "joined the group call")
            return
        }
        if previous != nil, current == nil {
            enqueue(participant.participantId, phrase: "left the group call")
            return
        }
        guard let previous, let current else { return }

        if previous.isMutedForAllUsers != current.isMutedForAllUsers {
            enqueue(
                participant.participantId,
                phrase: "microphone is \(current.isMutedForAllUsers ? "off" : "on")",
                possessive: true,
            )
        }
        if previous.isHandRaised != current.isHandRaised {
            enqueue(
                participant.participantId,
                phrase: current.isHandRaised ? "raised a hand" : "lowered a hand",
            )
        }

        let previousCamera = previous.videoInfo
        let currentCamera = current.videoInfo
        if (previousCamera == nil) != (currentCamera == nil) {
            enqueue(
                participant.participantId,
                phrase: "camera is \(currentCamera == nil ? "off" : "on")",
                possessive: true,
            )
        } else if let previousCamera, let currentCamera,
                  previousCamera.isPaused != currentCamera.isPaused
        {
            enqueue(
                participant.participantId,
                phrase: "camera is \(currentCamera.isPaused ? "paused" : "on")",
                possessive: true,
            )
        }

        let wasSharingScreen = previous.screenSharingVideoInfo != nil
        let isSharingScreen = current.screenSharingVideoInfo != nil
        if wasSharingScreen != isSharingScreen {
            enqueue(
                participant.participantId,
                phrase: isSharingScreen ? "started sharing their screen" : "stopped sharing their screen",
            )
        }
    }

    // MARK: Private

    private let service: any TelegramService
    private var generation = UUID()
    private var isEnabled = false
    private var activationTask: Task<Void, Never>?
    private var announcementTask: Task<Void, Never>?
    private var pendingAnnouncements = [(participantId: MessageSender, phrase: String, possessive: Bool)]()
    private var cachedNames = [MessageSender: String]()

    private func enqueue(
        _ participantId: MessageSender,
        phrase: String,
        possessive: Bool = false,
    ) {
        pendingAnnouncements.append((participantId, phrase, possessive))
        guard announcementTask == nil else { return }
        let generation = generation
        announcementTask = Task { [weak self] in
            await self?.processAnnouncements(generation: generation)
        }
    }

    private func processAnnouncements(generation: UUID) async {
        while self.generation == generation, !pendingAnnouncements.isEmpty {
            let announcement = pendingAnnouncements.removeFirst()
            let name = await participantName(announcement.participantId)
            guard self.generation == generation, !Task.isCancelled else { return }

            do {
                try await Task.sleep(for: .milliseconds(300))
            } catch {
                return
            }
            guard self.generation == generation,
                  UIAccessibility.isVoiceOverRunning
            else { return }

            let text = announcement.possessive
                ? "\(name)'s \(announcement.phrase)"
                : "\(name) \(announcement.phrase)"
            UIAccessibility.post(notification: .announcement, argument: text)
        }
        guard self.generation == generation else { return }
        announcementTask = nil
    }

    private func participantName(_ participantId: MessageSender) async -> String {
        if let cachedName = cachedNames[participantId] {
            return cachedName
        }

        let name: String
        do {
            name =
                switch participantId {
                case .messageSenderUser(let sender):
                    try await telegramUserDisplayName(service.getUser(userId: sender.userId))
                case .messageSenderChat(let sender):
                    try await service.getChat(chatId: sender.chatId).title
                }
        } catch is CancellationError {
            return "Participant"
        } catch {
            log("[GroupCall] couldn't resolve participant name for accessibility: \(error)")
            return "Participant"
        }
        guard !Task.isCancelled else { return "Participant" }
        cachedNames[participantId] = name
        return name
    }
}
