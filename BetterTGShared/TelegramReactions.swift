// TelegramReactions.swift

import TDLibKit

func telegramAvailableReactions(_ available: AvailableReactions) -> [AvailableReaction] {
    guard available.unavailabilityReason == nil else { return [] }

    var seen = Set<ReactionType>()
    return (available.topReactions + available.recentReactions + available.popularReactions).filter {
        seen.insert($0.type).inserted
    }
}

func telegramReactionChoices(
    existing: [MessageReaction],
    available: [AvailableReaction],
) -> [ReactionType] {
    var seen = Set<ReactionType>()
    let chosen = existing.filter { $0.isChosen && telegramReactionCanBeRemoved($0.type) }.map(\.type)
    let offered = available.map(\.type).filter { type in
        !existing.contains { $0.type == type && $0.isChosen && !telegramReactionCanBeRemoved(type) }
    }
    return (chosen + offered).filter {
        seen.insert($0).inserted
    }
}

func telegramReactionCanBeRemoved(_ type: ReactionType) -> Bool {
    if case .reactionTypePaid = type {
        return false
    }
    return true
}

func telegramReactionSymbol(_ type: ReactionType) -> String {
    switch type {
    case .reactionTypeEmoji(let reaction):
        reaction.emoji
    case .reactionTypeCustomEmoji:
        "✦"
    case .reactionTypePaid:
        "⭐"
    }
}

func telegramReactionName(_ type: ReactionType) -> String {
    switch type {
    case .reactionTypeEmoji(let reaction):
        reaction.emoji
    case .reactionTypeCustomEmoji:
        "custom emoji"
    case .reactionTypePaid:
        "paid reaction"
    }
}

func telegramReactionActionTitle(_ type: ReactionType, existing: [MessageReaction]) -> String {
    let isRemovableAndChosen = telegramReactionCanBeRemoved(type)
        && existing.contains { $0.type == type && $0.isChosen }
    let verb = isRemovableAndChosen ? "Remove reaction" : "React with"
    return "\(verb) \(telegramReactionName(type))"
}

func telegramReactionDescription(_ reactions: [MessageReaction]) -> String? {
    guard !reactions.isEmpty else { return nil }
    let counts = reactions.map { "\(telegramReactionSymbol($0.type)) \($0.totalCount)" }.joined(separator: ", ")
    let chosen = reactions.filter(\.isChosen).map { telegramReactionSymbol($0.type) }
    if chosen.isEmpty {
        return "Reactions: \(counts)"
    }
    return "Reactions: \(counts). You reacted with \(chosen.joined(separator: ", "))"
}
