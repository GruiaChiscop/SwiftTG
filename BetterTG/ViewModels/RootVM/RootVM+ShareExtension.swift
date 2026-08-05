// RootVM+ShareExtension.swift

import Foundation
import TDLibKit
import UIKit

extension RootVM {
    /// Entry point from `SceneDelegate` for a `swifttg://share?id=<uuid>` launch. The id in the
    /// URL is really just a nudge to process now - `processPendingShareRequests()` picks up every
    /// request waiting in the App Group container, not just this one, in case more than one piece
    /// of content was shared before the app got a chance to open.
    func handleShareURL(_ url: URL) {
        guard url.scheme == "swifttg", url.host == "share" else { return }
        Task { await self.processPendingShareRequests() }
    }

    /// Also called on ordinary launch/foreground, in case a share was completed while the app
    /// wasn't running to receive the URL open at all.
    ///
    /// `@MainActor` matters here, not just for the TDLib calls inside: the app can trigger this
    /// from the `swifttg://share` URL open, the scene becoming active, and `.authorizationStateReady`
    /// all within moments of each other on a share hand-off. Without actor isolation, the
    /// check-then-set on `shareRequestProcessingTask` below is a plain read/write race - two
    /// concurrent callers could each see `nil` and both start processing the same pending request.
    @MainActor func processPendingShareRequests() async {
        guard shareRequestProcessingTask == nil else { return }
        let task = Task { @MainActor in
            defer { self.shareRequestProcessingTask = nil }
            // Bail without touching any pending request if TDLib never actually came up - leaving
            // the request files in place lets the next launch/`.authorizationStateReady` retry
            // them, instead of silently losing shares that arrived at a cold, not-yet-ready launch.
            guard await self.awaitReadyForShareSend() else { return }
            for id in ShareRequestStore.pendingRequestIds() {
                _ = await self.sendShareRequest(id: id)
            }
        }
        shareRequestProcessingTask = task
        await task.value
    }

    // MARK: Private

    /// Polls TDLib's own live authorization state rather than the persisted `loggedIn` flag -
    /// `loggedIn` is a `UserDefaults` snapshot from the *previous* session and reads back `true`
    /// immediately on a cold launch, well before TDLib has actually finished re-authorizing this
    /// session. Trusting it here raced share sends against TDLib startup and silently dropped them.
    private func awaitReadyForShareSend() async -> Bool {
        let deadline = Date().addingTimeInterval(40)
        while Date() < deadline {
            if case .authorizationStateReady = try? await service.getAuthorizationState() {
                return true
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return false
    }

    @MainActor private func sendShareRequest(id: String) async -> Bool {
        guard let request = ShareRequestStore.load(id: id),
              let filesDirectory = ShareRequestStore.filesDirectory(id: id)
        else { return false }

        let comment = request.comment?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fileURLs = request.files.map { filesDirectory.appending(path: $0) }
        guard !request.chatIds.isEmpty, !fileURLs.isEmpty || !(comment ?? "").isEmpty else {
            ShareRequestStore.delete(id: id)
            return true
        }

        let contents = shareContents(comment: comment, fileURLs: fileURLs)
        var destinations = [CustomChat]()
        var anyFailed = false
        for chatId in request.chatIds {
            guard let customChat = await getCustomChat(from: chatId) else {
                anyFailed = true
                continue
            }
            do {
                try await TelegramMessageSending.send(
                    service: service,
                    chatId: chatId,
                    contents: contents,
                    replyTo: nil,
                )
                destinations.append(customChat)
            } catch {
                anyFailed = true
            }
        }

        ShareRequestStore.delete(id: id)
        guard !destinations.isEmpty else {
            UIAccessibility.post(notification: .announcement, argument: "Couldn't send.")
            return false
        }
        UIAccessibility.post(notification: .announcement, argument: anyFailed ? "Sent to some chats." : "Sent.")
        return true
    }

    private func shareContents(comment: String?, fileURLs: [URL]) -> [InputMessageContent] {
        guard !fileURLs.isEmpty else {
            guard let comment, !comment.isEmpty else { return [] }
            return [TelegramMessageSending.textContent(FormattedText(entities: [], text: comment))]
        }

        return fileURLs.enumerated().map { index, url in
            // The comment rides along as the first file's caption, matching how Telegram itself
            // captions the lead item of a shared album rather than sending a separate text message.
            let caption = index == 0
                ? FormattedText(entities: [], text: comment ?? "")
                : FormattedText(entities: [], text: "")
            if isImageAttachment(url), let size = imagePixelSize(at: url) {
                return TelegramMessageSending.photoContent(
                    url: url,
                    caption: caption,
                    width: Int(size.width),
                    height: Int(size.height),
                )
            }
            return TelegramMessageSending.documentContent(url: url, caption: caption)
        }
    }
}
