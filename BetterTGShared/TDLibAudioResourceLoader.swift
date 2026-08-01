// TDLibAudioResourceLoader.swift

import AVFoundation
import Combine
import Foundation
@preconcurrency import TDLibKit
import UniformTypeIdentifiers

// MARK: - TDLibAudioResourceLoader

final class TDLibAudioResourceLoader: NSObject, AVAssetResourceLoaderDelegate, @unchecked Sendable {
    // MARK: Lifecycle

    init(
        file: File,
        mimeType: String,
        duration: Int,
        service: any TelegramService,
        onFileUpdate: @escaping @Sendable (File) -> Void,
        onFailure: @escaping @Sendable (Swift.Error) -> Void,
    ) {
        self.file = file
        self.mimeType = mimeType
        self.duration = duration
        self.service = service
        self.onFileUpdate = onFileUpdate
        self.onFailure = onFailure
        self.ownsDownload = !file.local.isDownloadingActive
        super.init()

        self.subscription = service.filePublisher(fileId: file.id)
            .receive(on: queue)
            .sink { [weak self] file in
                guard let self else { return }
                self.file = file
                self.onFileUpdate(file)
                processActiveRequest()
            }
    }

    deinit {
        subscription?.cancel()
    }

    // MARK: Internal

    let queue = DispatchQueue(label: "com.gruiachiscop.BetterTG.audio-resource-loader")

    var assetURL: URL {
        URL(string: "bettertg-audio://file/\(file.id)")!
    }

    func cancel(download: Bool = true) {
        queue.async { [weak self] in
            guard let self else { return }
            downloadTask?.cancel()
            downloadTask = nil
            let requests = pendingRequests
            pendingRequests.removeAll()
            activeRequest = nil
            for request in requests {
                request.loadingRequest.finishLoading(with: URLError(.cancelled))
            }
            guard download, ownsDownload, !file.local.isDownloadingCompleted else { return }
            Task {
                _ = try? await self.service.cancelDownloadFile(fileId: self.file.id, onlyIfPending: false)
            }
        }
    }

    // MARK: AVAssetResourceLoaderDelegate

    func resourceLoader(
        _: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest,
    ) -> Bool {
        configureContentInformation(for: loadingRequest)
        guard let dataRequest = loadingRequest.dataRequest else {
            loadingRequest.finishLoading()
            return true
        }

        let startOffset = max(
            0,
            dataRequest.currentOffset != 0
                ? dataRequest.currentOffset
                : dataRequest.requestedOffset,
        )
        let totalSize = fileSize
        guard totalSize > 0, startOffset < totalSize else {
            loadingRequest.finishLoading(with: TDLibAudioStreamingError.invalidFileSize)
            return true
        }
        let requestedLength = max(1, Int64(dataRequest.requestedLength))
        let endOffset = startOffset + min(totalSize - startOffset, requestedLength)
        pendingRequests.append(PendingRequest(
            loadingRequest: loadingRequest,
            nextOffset: startOffset,
            endOffset: endOffset,
        ))
        startNextRequestIfNeeded()
        return true
    }

    func resourceLoader(
        _: AVAssetResourceLoader,
        didCancel loadingRequest: AVAssetResourceLoadingRequest,
    ) {
        let identifier = ObjectIdentifier(loadingRequest)
        pendingRequests.removeAll { ObjectIdentifier($0.loadingRequest) == identifier }
        if ObjectIdentifier(activeRequest?.loadingRequest ?? loadingRequest) == identifier {
            downloadTask?.cancel()
            downloadTask = nil
            activeRequest = nil
            startNextRequestIfNeeded()
        }
    }

    // MARK: Private

    private final class PendingRequest {
        // MARK: Lifecycle

        init(loadingRequest: AVAssetResourceLoadingRequest, nextOffset: Int64, endOffset: Int64) {
            self.loadingRequest = loadingRequest
            self.nextOffset = nextOffset
            self.endOffset = endOffset
        }

        // MARK: Internal

        let loadingRequest: AVAssetResourceLoadingRequest
        var nextOffset: Int64
        let endOffset: Int64
        var requestedThrough: Int64 = 0
    }

    private let duration: Int
    private let mimeType: String
    private let onFailure: @Sendable (Swift.Error) -> Void
    private let onFileUpdate: @Sendable (File) -> Void
    private let ownsDownload: Bool
    private let service: any TelegramService

    private var activeRequest: PendingRequest?
    private var downloadTask: Task<Void, Never>?
    private var file: File
    private var pendingRequests = [PendingRequest]()
    private var subscription: AnyCancellable?

    private var fileSize: Int64 {
        max(file.size, file.expectedSize)
    }

    private var preferredBufferSize: Int64 {
        guard duration > 0, fileSize > 0 else { return 1 * 1024 * 1024 }
        let fifteenSeconds = Int64(Double(fileSize) / Double(duration) * 15)
        return min(4 * 1024 * 1024, max(256 * 1024, fifteenSeconds))
    }

    private func configureContentInformation(for request: AVAssetResourceLoadingRequest) {
        guard let information = request.contentInformationRequest else { return }
        information.contentLength = fileSize
        information.isByteRangeAccessSupported = true
        information.contentType = UTType(mimeType: mimeType)?.identifier ?? UTType.audio.identifier
    }

    private func startNextRequestIfNeeded() {
        guard activeRequest == nil, !pendingRequests.isEmpty else { return }
        activeRequest = pendingRequests[0]
        processActiveRequest()
    }

    private func processActiveRequest() {
        guard let request = activeRequest else { return }
        do {
            try provideAvailableData(to: request)
            if request.nextOffset >= request.endOffset {
                finishActiveRequest()
                return
            }
            if file.local.isDownloadingActive, request.nextOffset < request.requestedThrough {
                return
            }
            requestNextChunk(for: request)
        } catch {
            failActiveRequest(error)
        }
    }

    private func provideAvailableData(to request: PendingRequest) throws {
        let availableRange: Range<Int64>
        if file.local.isDownloadingCompleted {
            availableRange = 0..<fileSize
        } else {
            let start = file.local.downloadOffset
            availableRange = start..<(start + file.local.downloadedPrefixSize)
        }
        guard availableRange.contains(request.nextOffset), !file.local.path.isEmpty else { return }
        let readableEnd = min(request.endOffset, availableRange.upperBound)
        let byteCount = readableEnd - request.nextOffset
        guard byteCount > 0 else { return }

        let handle = try FileHandle(forReadingFrom: URL(filePath: file.local.path))
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(request.nextOffset))
        guard let data = try handle.read(upToCount: Int(byteCount)), !data.isEmpty else { return }
        request.loadingRequest.dataRequest?.respond(with: data)
        request.nextOffset += Int64(data.count)
    }

    private func requestNextChunk(for request: PendingRequest) {
        guard downloadTask == nil else { return }
        let remaining = request.endOffset - request.nextOffset
        guard remaining > 0 else { return }
        let length = min(remaining, preferredBufferSize)
        request.requestedThrough = request.nextOffset + length
        let offset = request.nextOffset
        downloadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let updatedFile = try await service.downloadFile(
                    fileId: file.id,
                    limit: length,
                    offset: offset,
                    priority: 32,
                    synchronous: false,
                )
                queue.async { [weak self] in
                    guard let self else { return }
                    downloadTask = nil
                    file = updatedFile
                    onFileUpdate(updatedFile)
                    processActiveRequest()
                }
            } catch {
                queue.async { [weak self] in
                    self?.downloadTask = nil
                    self?.failActiveRequest(error)
                }
            }
        }
    }

    private func finishActiveRequest() {
        guard let request = activeRequest else { return }
        request.loadingRequest.finishLoading()
        pendingRequests.removeAll { $0 === request }
        activeRequest = nil
        downloadTask = nil
        startNextRequestIfNeeded()
    }

    private func failActiveRequest(_ error: Swift.Error) {
        guard let request = activeRequest else { return }
        request.loadingRequest.finishLoading(with: error)
        pendingRequests.removeAll { $0 === request }
        activeRequest = nil
        downloadTask?.cancel()
        downloadTask = nil
        onFailure(error)
        startNextRequestIfNeeded()
    }
}

// MARK: - TDLibAudioStreamingError

private enum TDLibAudioStreamingError: Swift.Error {
    case invalidFileSize
}
