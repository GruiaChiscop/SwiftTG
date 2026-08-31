// TelegramFileStore.swift

import Combine
import Foundation
@preconcurrency import TDLibKit

final class TelegramFileStore: @unchecked Sendable {
    // MARK: Internal

    /// Delivered on the main thread - `subject` is written from `queue` (the store's private
    /// background queue), but every consumer is a SwiftUI `.onReceive`/`@Observable` update,
    /// which requires the main thread.
    func publisher(fileId: Int) -> AnyPublisher<File, Never> {
        queue.sync {
            let subject: CurrentValueSubject<File?, Never>
            if let existingSubject = subjects[fileId] {
                subject = existingSubject
            } else {
                subject = CurrentValueSubject(files[fileId])
                subjects[fileId] = subject
            }
            return subject.compactMap(\.self).receive(on: DispatchQueue.main).eraseToAnyPublisher()
        }
    }

    func mergeInitial(_ file: File) {
        queue.async {
            if let current = self.files[file.id], !Self.isMoreComplete(file, than: current) {
                return
            }
            self.publish(file)
        }
    }

    func reset() {
        queue.async {
            self.files.removeAll()
            let existingSubjects = self.subjects.values
            self.subjects.removeAll()
            for subject in existingSubjects {
                subject.send(nil)
            }
        }
    }

    func reduce(_ update: Update) {
        guard case .updateFile(let value) = update else { return }
        queue.async {
            self.publish(value.file)
        }
    }

    // MARK: Private

    private let queue = DispatchQueue(label: "com.gruiachiscop.BetterTG.telegram-files")
    private var files = [Int: File]()
    private var subjects = [Int: CurrentValueSubject<File?, Never>]()

    private static func isMoreComplete(_ candidate: File, than current: File) -> Bool {
        if candidate.local.isDownloadingCompleted != current.local.isDownloadingCompleted {
            return candidate.local.isDownloadingCompleted
        }
        if candidate.local.path.isEmpty != current.local.path.isEmpty {
            return !candidate.local.path.isEmpty
        }
        return candidate.local.downloadedSize > current.local.downloadedSize
    }

    private func publish(_ file: File) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard files[file.id] != file else { return }
        files[file.id] = file
        subjects[file.id]?.send(file)
    }
}
