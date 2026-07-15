// AsyncTdFile.swift

import SwiftUI
import TDLibKit

struct AsyncTdFile<Content: View, Placeholder: View>: View {
    // MARK: Lifecycle

    init(
        id: Int,
        service: any TelegramService = TDLib.shared.service,
        @ViewBuilder content: @escaping (File) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder,
    ) {
        self.id = id
        self.service = service
        self.content = content
        self.placeholder = placeholder
    }

    // MARK: Internal

    let id: Int
    @ViewBuilder let content: (File) -> Content
    @ViewBuilder let placeholder: () -> Placeholder
    
    var body: some View {
        ZStack {
            Group {
                if let file, file.local.isDownloadingCompleted {
                    content(file)
                } else {
                    placeholder()
                }
            }
            .transition(.opacity)
        }
        .task(id: id) { await download(id) }
        .onReceive(service.filePublisher(fileId: id)) { updatedFile in
            withAnimation { file = updatedFile }
        }
    }
    
    // MARK: Private

    @State private var file: File?

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
}
