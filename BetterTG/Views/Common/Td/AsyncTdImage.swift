// AsyncTdImage.swift

import ImageIO
import SwiftUI
import TDLibKit

// MARK: - AsyncTdImage

struct AsyncTdImage<Content: View, Placeholder: View>: View {
    init(
        id: Int,
        maxPixelSize: Int = 1024,
        service: any TelegramService = TDLib.shared.service,
        @ViewBuilder content: @escaping (Image, File) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.id = id
        self.maxPixelSize = maxPixelSize
        self.service = service
        self.content = content
        self.placeholder = placeholder
    }

    // MARK: Internal

    let id: Int
    @ViewBuilder let content: (Image, File) -> Content
    @ViewBuilder let placeholder: () -> Placeholder
    
    var body: some View {
        ZStack {
            if let image, let file {
                content(image, file)
            } else {
                placeholder()
            }
        }
        .task(id: id) { await download(id) }
        .onReceive(service.filePublisher(fileId: id)) { file in
            Task.main { await setImage(from: file) }
        }
    }
    
    // MARK: Private

    @State private var file: File?
    @State private var image: Image?
    @State private var decodedLocalPath: String?
    private let maxPixelSize: Int
    private let service: any TelegramService
    
    private func download(_ id: Int? = nil) async {
        do {
            _ = try await service.downloadFile(
                fileId: id ?? self.id,
                limit: 0,
                offset: 0,
                priority: 1,
                synchronous: false,
            )
        } catch {
            log("Error downloading file: \(error)")
        }
    }
    
    @MainActor private func setImage(from file: File) async {
        guard file.local.isDownloadingCompleted else { return }
        let localPath = file.local.path
        guard !localPath.isEmpty, decodedLocalPath != localPath else { return }
        decodedLocalPath = localPath
        guard let uiImage = await Task.detached(priority: .userInitiated, operation: {
            downsampledImage(at: URL(filePath: localPath), maxPixelSize: maxPixelSize)
        })
        .value else {
            decodedLocalPath = nil
            return
        }

        // An animated replacement invalidates more of the accessibility tree and
        // is especially noticeable while VoiceOver is traversing the message list.
        self.file = file
        image = Image(uiImage: uiImage)
    }
}
