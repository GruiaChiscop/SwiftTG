// TelegramAnimationLibrary.swift

import TDLibKit

func telegramUniqueAnimations(_ animations: [TDLibKit.Animation]) -> [TDLibKit.Animation] {
    var fileIds = Set<Int>()
    return animations.filter { fileIds.insert($0.animation.id).inserted }
}

func telegramAnimations(from results: InlineQueryResults) -> [TDLibKit.Animation] {
    results.results.compactMap { result in
        guard case .inlineQueryResultAnimation(let animationResult) = result else { return nil }
        return animationResult.animation
    }
}
