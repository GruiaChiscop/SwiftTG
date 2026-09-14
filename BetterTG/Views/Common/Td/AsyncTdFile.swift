// AsyncTdFile.swift

import SwiftUI
import TDLibKit

struct AsyncTdFile<Content: View, Placeholder: View>: View {
    // MARK: Lifecycle

    init(
        id: Int,
        service: any TelegramService = TDLib.shared.service,
        isPaused: Bool = false,
        autoDownloads: Bool = true,
        downloadRequest: Int = 0,
        @ViewBuilder content: @escaping (File) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder,
    ) {
        self.id = id
        self.service = service
        self.isPaused = isPaused
        self.autoDownloads = autoDownloads
        self.downloadRequest = downloadRequest
        self.content = content
        self.placeholder = { _ in placeholder() }
    }

    init(
        id: Int,
        service: any TelegramService = TDLib.shared.service,
        isPaused: Bool = false,
        autoDownloads: Bool = true,
        downloadRequest: Int = 0,
        @ViewBuilder content: @escaping (File) -> Content,
        @ViewBuilder placeholder: @escaping (File?) -> Placeholder,
    ) {
        self.id = id
        self.service = service
        self.isPaused = isPaused
        self.autoDownloads = autoDownloads
        self.downloadRequest = downloadRequest
        self.content = content
        self.placeholder = placeholder
    }

    // MARK: Internal

    let id: Int
    let isPaused: Bool
    /// When `false`, the file isn't fetched just because this view appeared - only an increment
    /// to `downloadRequest` (a caller-owned "tap to download" trigger) starts the transfer.
    let autoDownloads: Bool
    let downloadRequest: Int
    @ViewBuilder let content: (File) -> Content
    @ViewBuilder let placeholder: (File?) -> Placeholder

    var body: some View {
        ZStack {
            Group {
                if let file,
                   file.local.isDownloadingCompleted,
                   !file.local.path.isEmpty
                {
                    content(file)
                } else {
                    placeholder(file)
                }
            }
            .transition(.opacity)
        }
        .task(id: "\(id):\(isPaused):\(autoDownloads):\(downloadRequest)") {
            guard !isPaused, autoDownloads || downloadRequest > 0 else { return }
            await download(id)
        }
        .onReceive(service.filePublisher(fileId: id)) { updatedFile in
            withAnimation { file = updatedFile }
        }
    }
    
    // MARK: Private

    @State private var file: File?

    private let service: any TelegramService
    
    @MainActor private func download(_ id: Int? = nil) async {
        do {
            let downloadedFile = try await service.downloadFile(
                fileId: id ?? self.id,
                limit: 0,
                offset: 0,
                priority: 1,
                synchronous: false,
            )
            file = downloadedFile
        } catch {
            log("Error downloading file: \(error)")
        }
    }
}
