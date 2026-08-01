// MacComposerTextField.swift

import AppKit
import SwiftUI

// MARK: - MacComposerTextField

struct MacComposerTextField: NSViewRepresentable {
    // MARK: Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        // MARK: Lifecycle

        init(parent: MacComposerTextField) {
            self.parent = parent
        }

        // MARK: Internal

        var parent: MacComposerTextField

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            textView.needsDisplay = true
        }
    }

    @Binding var text: String

    let accessibilityLabel: String
    let onPasteFiles: ([URL]) -> Bool
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = ComposerTextView(frame: .zero)
        textView.delegate = context.coordinator
        textView.onPasteFiles = onPasteFiles
        textView.onSubmit = onSubmit
        textView.isRichText = false
        textView.isAutomaticLinkDetectionEnabled = true
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.font = .preferredFont(forTextStyle: .body)
        textView.placeholder = accessibilityLabel
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = NSSize(width: 5, height: 5)
        textView.setAccessibilityLabel(accessibilityLabel)

        let scrollView = NSScrollView()
        scrollView.borderType = .bezelBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? ComposerTextView else { return }
        context.coordinator.parent = self
        textView.onPasteFiles = onPasteFiles
        textView.onSubmit = onSubmit
        textView.placeholder = accessibilityLabel
        textView.setAccessibilityLabel(accessibilityLabel)
        if textView.string != text {
            textView.string = text
        }
    }
}

// MARK: - ComposerTextView

private final class ComposerTextView: NSTextView {
    // MARK: Internal

    var onPasteFiles: (([URL]) -> Bool)?
    var onSubmit: (() -> Void)?
    var placeholder = ""

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholder.isEmpty else { return }
        placeholder.draw(
            at: NSPoint(x: textContainerInset.width + 2, y: textContainerInset.height),
            withAttributes: [
                .font: font ?? NSFont.preferredFont(forTextStyle: .body),
                .foregroundColor: NSColor.placeholderTextColor,
            ],
        )
    }

    override func paste(_ sender: Any?) {
        let urls = pastedFileURLs(from: .general)
        if !urls.isEmpty, onPasteFiles?(urls) == true {
            NSAccessibility.post(
                element: self,
                notification: .announcementRequested,
                userInfo: [
                    .announcement: urls.count == 1
                        ? "Attached \(urls[0].lastPathComponent)"
                        : "Attached \(urls.count) files",
                    .priority: NSAccessibilityPriorityLevel.high.rawValue,
                ],
            )
            return
        }
        super.paste(sender)
    }

    override func keyDown(with event: NSEvent) {
        let isUnmodifiedReturn = (event.keyCode == 36 || event.keyCode == 76)
            && event.modifierFlags.intersection([.shift, .option, .control, .command]).isEmpty
        if isUnmodifiedReturn {
            onSubmit?()
        } else {
            super.keyDown(with: event)
        }
    }

    // MARK: Private

    private func pastedFileURLs(from pasteboard: NSPasteboard) -> [URL] {
        if let objects = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true],
        ) as? [URL] {
            let files = objects.filter(\.isExistingFile)
            if !files.isEmpty {
                return files
            }
        }

        if let image = NSImage(pasteboard: pasteboard),
           let url = writePastedImage(image)
        {
            return [url]
        }

        guard let string = pasteboard.string(forType: .string) else { return [] }
        let candidates = string
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !candidates.isEmpty else { return [] }
        let urls = candidates.compactMap(fileURL(fromPathText:))
        return urls.count == candidates.count ? urls : []
    }

    private func fileURL(fromPathText text: String) -> URL? {
        var path = text
        if path.count >= 2,
           path.first == "\"" && path.last == "\"" || path.first == "'" && path.last == "'"
        {
            path.removeFirst()
            path.removeLast()
        }
        path = path.replacingOccurrences(of: "\\ ", with: " ")
        let url: URL =
            if let parsed = URL(string: path), parsed.isFileURL {
                parsed
            } else {
                URL(filePath: (path as NSString).expandingTildeInPath)
            }
        return url.isExistingFile ? url : nil
    }

    private func writePastedImage(_ image: NSImage) -> URL? {
        guard let tiff = image.tiffRepresentation,
              let representation = NSBitmapImageRep(data: tiff),
              let data = representation.representation(using: .png, properties: [:])
        else { return nil }
        let directory = FileManager.default
            .temporaryDirectory
            .appending(path: "BetterTGPastedAttachments", directoryHint: .isDirectory)
        let url = directory.appending(path: "image-\(UUID().uuidString).png")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}

private extension URL {
    var isExistingFile: Bool {
        guard isFileURL else { return false }
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && !isDirectory.boolValue
    }
}
