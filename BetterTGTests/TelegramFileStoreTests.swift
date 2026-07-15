// TelegramFileStoreTests.swift

@testable import BetterTG
import Combine
import Foundation
import TDLibKit
import Testing

struct TelegramFileStoreTests {
    // MARK: Internal

    @Test func `initial file is published and replayed`() throws {
        let store = TelegramFileStore()
        let file = TDLibFixtures.file(
            id: 1,
            downloadedSize: 100,
            isDownloadingCompleted: true,
            path: "/tmp/file",
        )
        store.mergeInitial(file)

        let received = try waitForFile(store: store, fileId: file.id) { $0 == file }
        #expect(received == file)

        var replayed: File?
        let cancellable = store.publisher(fileId: file.id).first().sink { replayed = $0 }
        withExtendedLifetime(cancellable) {}
        #expect(replayed == file)
    }

    @Test func `update is delivered only to its own file publisher`() throws {
        let store = TelegramFileStore()
        let file = TDLibFixtures.file(id: 10, downloadedSize: 40)
        var unrelatedFileWasReceived = false
        let unrelatedCancellable = store.publisher(fileId: 11).sink { _ in
            unrelatedFileWasReceived = true
        }

        store.reduce(.updateFile(.init(file: file)))
        let received = try waitForFile(store: store, fileId: file.id) { $0 == file }

        withExtendedLifetime(unrelatedCancellable) {}
        #expect(received == file)
        #expect(!unrelatedFileWasReceived)
    }

    @Test func `stale initial result does not overwrite A completed update`() throws {
        let store = TelegramFileStore()
        let completed = TDLibFixtures.file(
            id: 20,
            downloadedSize: 100,
            isDownloadingCompleted: true,
            path: "/tmp/completed",
        )
        let staleInitial = TDLibFixtures.file(id: 20, downloadedSize: 20)
        store.reduce(.updateFile(.init(file: completed)))
        _ = try waitForFile(store: store, fileId: completed.id) { $0 == completed }

        store.mergeInitial(staleInitial)

        let replayed = try waitForFile(store: store, fileId: completed.id) { _ in true }
        #expect(replayed == completed)
    }

    @Test func `authoritative update can replace previous state`() throws {
        let store = TelegramFileStore()
        let completed = TDLibFixtures.file(
            id: 30,
            downloadedSize: 100,
            isDownloadingCompleted: true,
            path: "/tmp/completed",
        )
        let reset = TDLibFixtures.file(id: 30, downloadedSize: 0)
        store.mergeInitial(completed)
        _ = try waitForFile(store: store, fileId: completed.id) { $0 == completed }

        store.reduce(.updateFile(.init(file: reset)))

        let received = try waitForFile(store: store, fileId: reset.id) { $0 == reset }
        #expect(received == reset)
    }

    // MARK: Private

    private func waitForFile(
        store: TelegramFileStore,
        fileId: Int,
        matching predicate: @escaping (File) -> Bool,
    ) throws -> File {
        let semaphore = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var result: File?
        var didSignal = false
        let cancellable = store.publisher(fileId: fileId).sink { file in
            lock.lock()
            defer { lock.unlock() }
            guard !didSignal, predicate(file) else { return }
            didSignal = true
            result = file
            semaphore.signal()
        }

        let waitResult = semaphore.wait(timeout: .now() + 2)
        withExtendedLifetime(cancellable) {}
        #expect(waitResult == .success)
        return try #require(result)
    }
}
