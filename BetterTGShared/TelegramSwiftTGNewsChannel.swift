// TelegramSwiftTGNewsChannel.swift

import Foundation

/// SwiftTG's own Telegram announcement channel, linked from the "What's New in SwiftTG" button -
/// mirrors the news-channel button SwiftGram and other Telegram forks show in place of a
/// traditional in-app changelog. The app's own `t.me` deep-link handling (see
/// `TelegramDeepLink.isTelegramLink`) opens this in-app as a chat rather than in a browser.
enum TelegramSwiftTGNewsChannel {
    static let url = URL(string: "https://t.me/swifttgofficial")!
}
