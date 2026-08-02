// TelegramDocumentExportTests.swift

@testable import BetterTG
import Foundation
import Testing

struct TelegramDocumentExportTests {
    @Test func `file name discards paths and rejects empty components`() {
        #expect(TelegramDocumentExport.fileName("folder/report.pdf") == "report.pdf")
        #expect(TelegramDocumentExport.fileName("  ") == "Document")
        #expect(TelegramDocumentExport.fileName("..") == "Document")
    }

    @Test func `staged export preserves the original contents and suggested name`() async throws {
        let temporaryDirectory = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let sourceURL = temporaryDirectory.appendingPathComponent("tdlib-cache-name")
        let contents = Data("BetterTG document".utf8)
        try contents.write(to: sourceURL)

        let stagedURL = try await TelegramDocumentExport.stagedURL(
            sourceURL: sourceURL,
            suggestedFileName: "report.txt",
            identifier: UUID().uuidString,
        )
        defer { try? FileManager.default.removeItem(at: stagedURL.deletingLastPathComponent()) }

        #expect(stagedURL.lastPathComponent == "report.txt")
        #expect(try Data(contentsOf: stagedURL) == contents)
    }

    @Test func `copy replaces an existing destination`() async throws {
        let temporaryDirectory = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let sourceURL = temporaryDirectory.appendingPathComponent("source")
        let destinationURL = temporaryDirectory.appendingPathComponent("destination")
        try Data("new".utf8).write(to: sourceURL)
        try Data("old".utf8).write(to: destinationURL)

        try await TelegramDocumentExport.copyFile(from: sourceURL, to: destinationURL)

        #expect(try Data(contentsOf: destinationURL) == Data("new".utf8))
    }

    @Test func `forced staging copy is independent from its source`() async throws {
        let temporaryDirectory = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let sourceURL = temporaryDirectory.appendingPathComponent("cloud-document.txt")
        try Data("original".utf8).write(to: sourceURL)

        let stagedURL = try await TelegramDocumentExport.stagedURL(
            sourceURL: sourceURL,
            suggestedFileName: sourceURL.lastPathComponent,
            identifier: UUID().uuidString,
            forceCopy: true,
        )
        defer { try? FileManager.default.removeItem(at: stagedURL.deletingLastPathComponent()) }

        try Data("changed".utf8).write(to: sourceURL)

        #expect(try Data(contentsOf: stagedURL) == Data("original".utf8))
    }
}
