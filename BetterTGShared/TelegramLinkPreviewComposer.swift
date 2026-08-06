// TelegramLinkPreviewComposer.swift

import Combine
import Foundation
import TDLibKit

@MainActor @Observable final class TelegramLinkPreviewComposer {
    // MARK: Lifecycle

    init(
        service: any TelegramService,
        preview: LinkPreview? = nil,
        options: LinkPreviewOptions? = nil,
    ) {
        self.service = service
        self.preview = preview
        self.options = options
        self.requestSubscription = requestSubject
            // TDLib explicitly asks clients not to request previews too often. This is a
            // cancellable trailing-edge debounce of composer changes, not a blocking sleep.
                .debounce(for: .milliseconds(400), scheduler: DispatchQueue.main)
                .sink { [weak self] request in
                    Task { @MainActor [weak self] in
                        self?.load(request)
                    }
                }
    }

    // MARK: Internal

    private(set) var preview: LinkPreview?
    private(set) var options: LinkPreviewOptions?
    private(set) var isLoading = false

    var presentation: TelegramLinkPreviewPresentation? {
        preview.map(TelegramLinkPreviewPresentation.init)
    }

    var showsAboveText: Bool {
        guard let preview else { return false }
        return options?.showAboveText ?? preview.showAboveText
    }

    var showsLargeMedia: Bool {
        guard let preview else { return false }
        return options?.forceLargeMedia == true
            || (options?.forceSmallMedia != true && preview.showLargeMedia)
    }

    static func firstWebURL(in text: FormattedText) -> URL? {
        let range = NSRange(text.text.startIndex..., in: text.text)
        let entityCandidates = TelegramTextFormatting.links(in: text).compactMap { link -> URLCandidate? in
            guard isWebURL(link.url) else { return nil }
            return URLCandidate(offset: link.offset, prefersDetectedText: false, url: link.url)
        }
        let detectedCandidates = linkDetector?.matches(in: text.text, range: range).compactMap { match
            -> URLCandidate? in
            guard let url = match.url, isWebURL(url) else { return nil }
            return URLCandidate(offset: match.range.location, prefersDetectedText: true, url: url)
        } ?? []

        return (entityCandidates + detectedCandidates)
            .min { lhs, rhs in
                if lhs.offset != rhs.offset {
                    return lhs.offset < rhs.offset
                }
                return lhs.prefersDetectedText && !rhs.prefersDetectedText
            }?.url
    }

    func configure(preview: LinkPreview?, options: LinkPreviewOptions?) {
        requestTask?.cancel()
        requestGeneration &+= 1
        self.preview = preview
        self.options = options
        currentURL = nil
        currentText = nil
        isLoading = false
    }

    func update(text: FormattedText) {
        currentText = text
        guard let url = Self.firstWebURL(in: text) else {
            clearForMissingURL()
            return
        }

        let normalizedURL = url.absoluteString
        if options?.isDisabled == true {
            let disabledURL = Self.normalizedURL(options?.url)
            if disabledURL == nil || disabledURL.map({ telegramURLsReferToSameResource($0, url) }) == true {
                currentURL = normalizedURL
                preview = nil
                requestTask?.cancel()
                isLoading = false
                return
            }
            options = nil
        } else if let existingOptions = options,
                  let optionURL = Self.normalizedURL(existingOptions.url),
                  !telegramURLsReferToSameResource(optionURL, url)
        {
            options = LinkPreviewOptions(
                forceLargeMedia: existingOptions.forceLargeMedia,
                forceSmallMedia: existingOptions.forceSmallMedia,
                isDisabled: false,
                showAboveText: existingOptions.showAboveText,
                url: normalizedURL,
            )
        }

        currentURL = normalizedURL
        if let previewURL = Self.normalizedURL(preview?.url), telegramURLsReferToSameResource(previewURL, url) {
            return
        }
        preview = nil
        requestSubject.send(Request(text: text, options: options, url: normalizedURL))
    }

    func dismiss() {
        guard let currentURL else { return }
        requestTask?.cancel()
        requestGeneration &+= 1
        preview = nil
        isLoading = false
        options = LinkPreviewOptions(
            forceLargeMedia: false,
            forceSmallMedia: false,
            isDisabled: true,
            showAboveText: false,
            url: currentURL,
        )
    }

    func togglePosition() {
        guard let preview, let currentURL, let currentText else { return }
        let currentValue = options?.showAboveText ?? preview.showAboveText
        options = LinkPreviewOptions(
            forceLargeMedia: options?.forceLargeMedia ?? false,
            forceSmallMedia: options?.forceSmallMedia ?? false,
            isDisabled: false,
            showAboveText: !currentValue,
            url: currentURL,
        )
        requestSubject.send(Request(text: currentText, options: options, url: currentURL))
    }

    func toggleMediaSize() {
        guard let preview, preview.hasLargeMedia, let currentURL, let currentText else { return }
        let currentlyLarge = options?.forceLargeMedia == true
            || (options?.forceSmallMedia != true && preview.showLargeMedia)
        options = LinkPreviewOptions(
            forceLargeMedia: !currentlyLarge,
            forceSmallMedia: currentlyLarge,
            isDisabled: false,
            showAboveText: options?.showAboveText ?? preview.showAboveText,
            url: currentURL,
        )
        requestSubject.send(Request(text: currentText, options: options, url: currentURL))
    }

    // MARK: Private

    private struct Request {
        let text: FormattedText
        let options: LinkPreviewOptions?
        let url: String
    }

    private struct URLCandidate {
        let offset: Int
        let prefersDetectedText: Bool
        let url: URL
    }

    private static let linkDetector = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.link.rawValue,
    )

    @ObservationIgnored private let service: any TelegramService
    @ObservationIgnored private let requestSubject = PassthroughSubject<Request, Never>()
    @ObservationIgnored private var requestSubscription: AnyCancellable?
    @ObservationIgnored private var requestTask: Task<Void, Never>?
    @ObservationIgnored private var requestGeneration: UInt64 = 0
    @ObservationIgnored private var currentText: FormattedText?
    @ObservationIgnored private var currentURL: String?

    private static func isWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    private static func normalizedURL(_ value: String?) -> URL? {
        guard let value, !value.isEmpty else { return nil }
        if let components = URLComponents(string: value), components.scheme != nil {
            return components.url
        }
        return URL(string: "https://\(value)")
    }

    private func clearForMissingURL() {
        requestTask?.cancel()
        requestGeneration &+= 1
        preview = nil
        options = nil
        currentURL = nil
        isLoading = false
    }

    @MainActor private func load(_ request: Request) {
        guard request.url == currentURL, request.options == options else { return }
        requestTask?.cancel()
        requestGeneration &+= 1
        let generation = requestGeneration
        isLoading = true
        requestTask = Task { [weak self, service] in
            let result = try? await service.getLinkPreview(
                linkPreviewOptions: request.options,
                text: request.text,
            )
            guard !Task.isCancelled,
                  let self,
                  generation == requestGeneration,
                  request.url == currentURL
            else { return }
            preview = result
            isLoading = false
        }
    }
}
