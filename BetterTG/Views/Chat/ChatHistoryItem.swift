// ChatHistoryItem.swift

import Foundation

// MARK: - ChatHistoryItem

@MainActor struct ChatHistoryItem: Identifiable {
    // MARK: Internal

    enum ID: Hashable {
        case day(Int64)
        case message(Int64)
        case unread(Int64)
    }

    enum Kind {
        case day(String)
        case message(CustomMessage, previous: CustomMessage?, next: CustomMessage?)
        case unread(count: Int, voiceOverFocusRequest: Int)
    }

    enum ContentSignature: Equatable {
        case day(String)
        case message(ObjectIdentifier, previous: ObjectIdentifier?, next: ObjectIdentifier?)
        case unread(Int, focusRequest: Int)
    }

    let id: ID
    let kind: Kind

    var contentSignature: ContentSignature {
        switch kind {
        case .day(let title):
            .day(title)
        case .message(let message, let previous, let next):
            .message(
                ObjectIdentifier(message),
                previous: previous.map(ObjectIdentifier.init),
                next: next.map(ObjectIdentifier.init),
            )
        case .unread(let count, let request):
            .unread(count, focusRequest: request)
        }
    }

    var messageId: Int64? {
        guard case .message(let message, _, _) = kind else { return nil }
        return message.id
    }

    static func makeItems(
        messages: [CustomMessage],
        unreadMessageId: Int64?,
        unreadCount: Int,
        unreadHeaderVoiceOverFocusRequest: Int,
    ) -> [ChatHistoryItem] {
        var items = [ChatHistoryItem]()
        items.reserveCapacity(messages.count + 2)

        for (index, message) in messages.enumerated() {
            let previous = messages[safe: index - 1]
            let next = messages[safe: index + 1]
            if startsNewDay(message, after: previous) {
                items.append(ChatHistoryItem(
                    id: .day(message.id),
                    kind: .day(telegramMessageDayHeading(message.message.date)),
                ))
            }
            if message.id == unreadMessageId {
                items.append(ChatHistoryItem(
                    id: .unread(message.id),
                    kind: .unread(
                        count: unreadCount,
                        voiceOverFocusRequest: unreadHeaderVoiceOverFocusRequest,
                    ),
                ))
            }
            items.append(ChatHistoryItem(
                id: .message(message.id),
                kind: .message(message, previous: previous, next: next),
            ))
        }
        return items
    }

    // MARK: Private

    private static func startsNewDay(_ message: CustomMessage, after previous: CustomMessage?) -> Bool {
        guard let previous else { return true }
        let date = Date(timeIntervalSince1970: TimeInterval(message.message.date))
        let previousDate = Date(timeIntervalSince1970: TimeInterval(previous.message.date))
        return !Calendar.autoupdatingCurrent.isDate(date, inSameDayAs: previousDate)
    }
}
