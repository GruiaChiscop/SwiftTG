// CustomMessage.swift

import SwiftUI
import TDLibKit

// MARK: - CustomMessage

@Observable final class CustomMessage {
    // MARK: Lifecycle

    init(
        message: Message,
        senderUser: User? = nil,
        replyUser: User? = nil,
        replySenderName: String? = nil,
        replyToMessage: Message? = nil,
        album: [Message] = [Message](),
        sendFailed: Bool = false,
        forwardedFrom: String? = nil,
        formattedText: FormattedText? = nil,
        properties: MessageProperties,
        canReact: Bool = false,
    ) {
        self.message = message
        self.senderUser = senderUser
        self.replyUser = replyUser
        self.replySenderName = replySenderName
        self.replyToMessage = replyToMessage
        self.album = album
        self.sendFailed = sendFailed
        self.forwardedFrom = forwardedFrom
        self.formattedText = formattedText
        self.properties = properties
        self.canReact = canReact
    }
    
    // MARK: Internal

    var message: Message
    var senderUser: User?
    var replyUser: User?
    var replySenderName: String?
    var replyToMessage: Message?
    var album = [Message]()
    var sendFailed = false
    var forwardedFrom: String?
    var formattedText: FormattedText?
    var properties: MessageProperties
    var canReact: Bool
    
    var date: Foundation.Date { Date(timeIntervalSince1970: TimeInterval(message.date)) }
    
    var messageVoiceNote: MessageVoiceNote? {
        if case .messageVoiceNote(let messageVoiceNote) = message.content {
            return messageVoiceNote
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
        hasher.combine(message)
        hasher.combine(senderUser)
        hasher.combine(replyUser)
        hasher.combine(replySenderName)
        hasher.combine(replyToMessage)
        hasher.combine(album)
        hasher.combine(sendFailed)
        hasher.combine(forwardedFrom)
        hasher.combine(formattedText)
        hasher.combine(properties)
    }
}

// MARK: Identifiable

extension CustomMessage: Identifiable {
    var id: Int64 { message.id }
}

// MARK: Equatable

extension CustomMessage: Equatable {
    static func == (lhs: CustomMessage, rhs: CustomMessage) -> Bool {
        lhs.hashValue == rhs.hashValue
    }
}
