// CustomMessage.swift

import SwiftUI
import TDLibKit

// MARK: - CustomMessage

@Observable final class CustomMessage {
    // MARK: Lifecycle

    init(
        message: Message,
        senderUser: User? = nil,
        senderChatTitle: String? = nil,
        replyUser: User? = nil,
        replySenderName: String? = nil,
        replyToMessage: Message? = nil,
        album: [Message] = [Message](),
        sendFailed: Bool = false,
        forwardedFrom: String? = nil,
        serviceMessageText: String? = nil,
        formattedText: FormattedText? = nil,
        properties: MessageProperties,
        availableReactions: [AvailableReaction] = [],
    ) {
        self.message = message
        self.senderUser = senderUser
        self.senderChatTitle = senderChatTitle
        self.replyUser = replyUser
        self.replySenderName = replySenderName
        self.replyToMessage = replyToMessage
        self.album = album
        self.sendFailed = sendFailed
        self.forwardedFrom = forwardedFrom
        self.serviceMessageText = serviceMessageText
        self.formattedText = formattedText
        self.properties = properties
        self.availableReactions = availableReactions
    }
    
    // MARK: Internal

    /// A row's TDLib snapshot is immutable because `message.id` is also its SwiftUI identity.
    /// A newer snapshot must produce a new CustomMessage instead of changing a mounted row's id.
    let message: Message
    var senderUser: User?
    /// The sender's chat title, resolved when the message was posted as a chat rather than a user
    /// (a channel post, or an anonymous admin post "as the group") - `senderUser` stays nil then.
    var senderChatTitle: String?
    var replyUser: User?
    var replySenderName: String?
    var replyToMessage: Message?
    var album = [Message]()
    var sendFailed = false
    var forwardedFrom: String?
    var serviceMessageText: String?
    var formattedText: FormattedText?
    var properties: MessageProperties
    var availableReactions: [AvailableReaction]
    
    var date: Foundation.Date { Date(timeIntervalSince1970: TimeInterval(message.date)) }
    
    var messageVoiceNote: MessageVoiceNote? {
        if case .messageVoiceNote(let messageVoiceNote) = message.content {
            return messageVoiceNote
        }
        return nil
    }

    var messageAudio: MessageAudio? {
        if case .messageAudio(let messageAudio) = message.content {
            return messageAudio
        }
        return nil
    }
    
    var messagePhoto: MessagePhoto? {
        if case .messagePhoto(let messagePhoto) = message.content {
            return messagePhoto
        }
        return nil
    }

    var messageVideo: MessageVideo? {
        if case .messageVideo(let messageVideo) = message.content {
            return messageVideo
        }
        return nil
    }

    var messageDocument: MessageDocument? {
        if case .messageDocument(let messageDocument) = message.content {
            return messageDocument
        }
        return nil
    }
}

// MARK: Hashable

extension CustomMessage: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: Identifiable

extension CustomMessage: Identifiable {
    var id: Int64 { message.id }
}

// MARK: Equatable

extension CustomMessage: Equatable {
    /// Reference identity, not id equality: `List`/`ForEach` use `Equatable` (when available) to
    /// decide whether a row needs to re-render for a given id. Comparing by `id` alone would make
    /// every re-render of an existing message (edits, reactions, pin changes - each producing a
    /// new `CustomMessage` instance per the note on `message` above) look unchanged to SwiftUI,
    /// leaving the row stuck showing whatever it rendered first.
    static func == (lhs: CustomMessage, rhs: CustomMessage) -> Bool {
        lhs === rhs
    }
}
