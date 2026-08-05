// ShareViewController.swift

import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Never touches TDLib - a second process can't open the same TDLib database directory the main
/// app already has locked. This only stages the shared content into the shared App Group
/// container; `RootVM.processPendingShareRequests()` picks it up and actually sends it the next
/// time SwiftTG itself is opened or foregrounded (a Share Extension can't launch its containing
/// app - see the removed `extensionContext.open` call this used to have).
final class ShareViewController: UIViewController {
    // MARK: Internal

    override func viewDidLoad() {
        super.viewDidLoad()
        Task { @MainActor in
            await loadInputItems()
            showPicker()
        }
    }

    // MARK: Private

    private let requestId = UUID().uuidString
    private var sharedText = ""
    private var stagedFileNames = [String]()

    private func loadInputItems() async {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else { return }
        for item in items {
            if let attributedText = item.attributedContentText?.string, !attributedText.isEmpty {
                appendSharedText(attributedText)
            }
            for provider in item.attachments ?? [] {
                await load(provider)
            }
        }
    }

    private func load(_ provider: NSItemProvider) async {
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            if let url = await loadItem(provider, typeIdentifier: UTType.url.identifier) as? URL, !url.isFileURL {
                appendSharedText(url.absoluteString)
                return
            }
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            if let text = await loadItem(provider, typeIdentifier: UTType.plainText.identifier) as? String {
                appendSharedText(text)
                return
            }
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            await stageFile(provider, typeIdentifier: UTType.image.identifier)
            return
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            await stageFile(provider, typeIdentifier: UTType.fileURL.identifier)
            return
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.data.identifier) {
            await stageFile(provider, typeIdentifier: UTType.data.identifier)
        }
    }

    private func appendSharedText(_ text: String) {
        sharedText = sharedText.isEmpty ? text : "\(sharedText)\n\(text)"
    }

    private func loadItem(_ provider: NSItemProvider, typeIdentifier: String) async -> NSSecureCoding? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, _ in
                continuation.resume(returning: item)
            }
        }
    }

    private func stageFile(_ provider: NSItemProvider, typeIdentifier: String) async {
        guard let item = await loadItem(provider, typeIdentifier: typeIdentifier),
              let filesDirectory = ShareRequestStore.filesDirectory(id: requestId)
        else { return }

        var sourceURL: URL?
        var rawData: Data?
        if let url = item as? URL {
            sourceURL = url
        } else if let nsURL = item as? NSURL {
            sourceURL = nsURL as URL
        } else if let image = item as? UIImage {
            rawData = image.jpegData(compressionQuality: 0.9)
        } else if let data = item as? Data {
            rawData = data
        }

        try? FileManager.default.createDirectory(at: filesDirectory, withIntermediateDirectories: true)

        if let sourceURL {
            // Files handed back for `.fileURL`/`.image` are often security-scoped (Files app,
            // iCloud Drive, third-party document providers) - reading them without this call fails
            // silently since the copy below is best-effort, dropping the attachment with no error.
            let didStartAccessing = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if didStartAccessing {
                    sourceURL.stopAccessingSecurityScopedResource()
                }
            }

            // Each file gets its own UUID-named subdirectory rather than a UUID-prefixed filename -
            // `TelegramMessageSending.documentContent` uploads via `inputFileLocal(path:)`, which has
            // no separate "display name" field, so TDLib shows whatever the file is actually named on
            // disk. A prefixed name would ship as the visible filename in the chat.
            let destinationName = "\(UUID().uuidString)/\(sourceURL.lastPathComponent)"
            let destination = filesDirectory.appending(path: destinationName)
            try? FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true,
            )
            guard (try? FileManager.default.copyItem(at: sourceURL, to: destination)) != nil else { return }
            stagedFileNames.append(destinationName)
        } else if let rawData {
            let destinationName = "\(UUID().uuidString).jpg"
            let destination = filesDirectory.appending(path: destinationName)
            guard (try? rawData.write(to: destination)) != nil else { return }
            stagedFileNames.append(destinationName)
        }
    }

    private func attachmentPreviews() -> [ShareAttachmentPreview] {
        guard let filesDirectory = ShareRequestStore.filesDirectory(id: requestId) else { return [] }
        return stagedFileNames.map { relativePath in
            let url = filesDirectory.appending(path: relativePath)
            return ShareAttachmentPreview(url: url, name: url.lastPathComponent, isImage: isImageAttachment(url))
        }
    }

    @MainActor private func showPicker() {
        let picker = ShareView(
            cachedChats: ShareChatCache.load(),
            initialComment: sharedText,
            attachments: attachmentPreviews(),
        ) { [weak self] chatIds, comment in
            self?.send(chatIds: chatIds, comment: comment)
        } onCancel: { [weak self] in
            guard let self else { return }
            // Files were already staged into the App Group container as soon as the share sheet
            // loaded (see `stageFile`, called from `viewDidLoad`) - without this, cancelling leaves
            // them behind forever, since the only other cleanup path is a successful send.
            ShareRequestStore.delete(id: requestId)
            extensionContext?.cancelRequest(
                withError: NSError(domain: "ShareViewController", code: NSUserCancelledError),
            )
        }

        let hosting = UIHostingController(rootView: picker)
        addChild(hosting)
        hosting.view.frame = view.bounds
        hosting.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(hosting.view)
        hosting.didMove(toParent: self)
    }

    private func send(chatIds: [Int64], comment: String) {
        let request = ShareRequest(
            id: requestId,
            createdAt: Date().timeIntervalSince1970,
            chatIds: chatIds,
            comment: comment.isEmpty ? nil : comment,
            files: stagedFileNames,
        )
        guard (try? ShareRequestStore.write(request)) != nil else {
            ShareRequestStore.delete(id: requestId)
            extensionContext?.cancelRequest(withError: NSError(domain: "ShareViewController", code: 1))
            return
        }

        // No `extensionContext.open(_:)` call here: Apple documents that method as usable only from
        // a Today widget - from a Share Extension it always reports failure and never actually
        // brings the containing app forward, no matter how it's sequenced against `completeRequest`.
        // The request just sits staged in the App Group container; `RootVM.processPendingShareRequests()`
        // picks it up the next time BetterTG itself is opened or foregrounded, by any means.
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
}
