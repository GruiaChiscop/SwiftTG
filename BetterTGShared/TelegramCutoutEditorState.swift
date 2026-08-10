// TelegramCutoutEditorState.swift

import Observation

@MainActor @Observable final class TelegramCutoutEditorState {
    // MARK: Internal

    var mode = TelegramCutoutMaskMode.erase
    var brushWidth = 0.08
    private(set) var strokes = [TelegramCutoutMaskStroke]()

    var canUndo: Bool { !undoHistory.isEmpty }
    var canRedo: Bool { !redoHistory.isEmpty }
    var canReset: Bool { !strokes.isEmpty }

    func addStroke(points: [TelegramEditorPoint]) {
        guard !points.isEmpty else { return }
        recordMutation()
        strokes.append(.init(points: points, width: brushWidth, mode: mode))
    }

    func undo() {
        guard let previous = undoHistory.popLast() else { return }
        redoHistory.append(strokes)
        strokes = previous
    }

    func redo() {
        guard let next = redoHistory.popLast() else { return }
        undoHistory.append(strokes)
        strokes = next
    }

    func resetEdits() {
        guard !strokes.isEmpty else { return }
        recordMutation()
        strokes.removeAll()
    }

    func prepareForNewPhoto() {
        strokes.removeAll()
        undoHistory.removeAll()
        redoHistory.removeAll()
        mode = .erase
    }

    // MARK: Private

    private static let maximumHistoryCount = 50

    private var undoHistory = [[TelegramCutoutMaskStroke]]()
    private var redoHistory = [[TelegramCutoutMaskStroke]]()

    private func recordMutation() {
        undoHistory.append(strokes)
        if undoHistory.count > Self.maximumHistoryCount {
            undoHistory.removeFirst(undoHistory.count - Self.maximumHistoryCount)
        }
        redoHistory.removeAll()
    }
}
