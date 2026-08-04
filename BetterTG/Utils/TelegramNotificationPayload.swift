// TelegramNotificationPayload.swift

import Foundation

// MARK: - TelegramNotificationTarget

struct TelegramNotificationTarget: Equatable {
    var chatIds = [Int64]()
    var userIds = [Int64]()
    var basicGroupIds = [Int64]()
    var supergroupIds = [Int64]()
    var messageId: Int64?

    var isEmpty: Bool {
        chatIds.isEmpty && userIds.isEmpty && basicGroupIds.isEmpty && supergroupIds.isEmpty
    }
}

// MARK: - TelegramNotificationPayload

enum TelegramNotificationPayload {
    // MARK: Internal

    static func target(from userInfo: [AnyHashable: Any]) -> TelegramNotificationTarget? {
        var target = TelegramNotificationTarget()

        appendValues(
            for: ["chat_id", "chatId", "chatID", "tdlib_chat_id", "thread-id", "threadId", "threadID"],
            from: userInfo,
            to: &target.chatIds,
        )
        appendValues(for: ["from_id", "fromId", "user_id", "userId"], from: userInfo, to: &target.userIds)
        appendValues(for: ["basic_group_id", "basicGroupId"], from: userInfo, to: &target.basicGroupIds)
        appendValues(
            for: ["channel_id", "channelId", "supergroup_id", "supergroupId"],
            from: userInfo,
            to: &target.supergroupIds,
        )

        target.messageId = firstInt64(
            for: ["tdlib_message_id", "message_id", "messageId", "msg_id", "msgId"],
            from: userInfo,
        )

        for json in rawPayloadObjects(from: userInfo) {
            mergeJSON(json, into: &target)
        }

        return target.isEmpty ? nil : target
    }

    // MARK: Private

    private static func mergeJSON(_ value: Any, into target: inout TelegramNotificationTarget) {
        if let dict = value as? [String: Any] {
            appendValue(dict["chat_id"] ?? dict["chatId"] ?? dict["chatID"], to: &target.chatIds)
            appendValue(dict["from_id"] ?? dict["fromId"] ?? dict["user_id"] ?? dict["userId"], to: &target.userIds)
            appendValue(dict["basic_group_id"] ?? dict["basicGroupId"], to: &target.basicGroupIds)
            appendValue(
                dict["channel_id"] ?? dict["channelId"] ?? dict["supergroup_id"] ?? dict["supergroupId"],
                to: &target.supergroupIds,
            )

            if target.messageId == nil {
                target.messageId = parseInt64(
                    dict["tdlib_message_id"] ?? dict["message_id"] ?? dict["messageId"] ?? dict["msg_id"] ??
                        dict["msgId"],
                )
            }

            if let message = dict["message"] as? [String: Any] {
                mergeJSON(message, into: &target)
            }
            for nested in dict.values {
                mergeJSON(nested, into: &target)
            }
        } else if let array = value as? [Any] {
            for nested in array {
                mergeJSON(nested, into: &target)
            }
        }
    }

    private static func appendValues(
        for keys: [String],
        from userInfo: [AnyHashable: Any],
        to values: inout [Int64],
    ) {
        let aps = userInfo["aps"] as? [AnyHashable: Any]
        for key in keys {
            appendValue(userInfo[key] ?? aps?[key], to: &values)
        }
    }

    private static func appendValue(_ value: Any?, to values: inout [Int64]) {
        guard let parsed = parseInt64(value), !values.contains(parsed) else { return }
        values.append(parsed)
    }

    private static func firstInt64(for keys: [String], from userInfo: [AnyHashable: Any]) -> Int64? {
        let aps = userInfo["aps"] as? [AnyHashable: Any]
        for key in keys {
            if let parsed = parseInt64(userInfo[key] ?? aps?[key]) {
                return parsed
            }
        }
        return nil
    }

    private static func rawPayloadObjects(from userInfo: [AnyHashable: Any]) -> [Any] {
        let aps = userInfo["aps"] as? [AnyHashable: Any]
        let rawValues = [
            userInfo["tg_raw"],
            userInfo["tgRaw"],
            userInfo["payload"],
            aps?["tg_raw"],
            aps?["tgRaw"],
            aps?["payload"],
        ]

        return rawValues.compactMap { value in
            guard let string = value as? String else { return nil }
            return decodeJSONObject(from: string)
        }
    }

    private static func decodeJSONObject(from raw: String) -> Any? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let candidates = [
            trimmed.data(using: .utf8),
            Data(base64Encoded: trimmed),
            Data(base64Encoded: base64URLNormalized(trimmed)),
        ].compactMap(\.self)

        for data in candidates {
            if let json = try? JSONSerialization.jsonObject(with: data) {
                return json
            }
        }
        return nil
    }

    private static func base64URLNormalized(_ value: String) -> String {
        var result = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while result.count % 4 != 0 {
            result.append("=")
        }
        return result
    }

    private static func parseInt64(_ value: Any?) -> Int64? {
        if let number = value as? NSNumber {
            return number.int64Value
        }
        if let int = value as? Int {
            return Int64(int)
        }
        if let int64 = value as? Int64 {
            return int64
        }
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("chat.") {
            return Int64(trimmed.dropFirst("chat.".count))
        }
        return Int64(trimmed)
    }
}
