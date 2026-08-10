// TelegramMediaEditorState.swift

import Observation
import SwiftUI

@MainActor @Observable final class TelegramMediaEditorState {
    // MARK: Internal

    var tool = TelegramMediaEditorTool.select
    var brushColor = Color.white
    var brushWidth = 0.012
    var timelineDuration = 0.0
    private(set) var strokes = [TelegramDrawingStroke]()
    private(set) var overlays = [TelegramMediaOverlay]()
    var selectedOverlayID: UUID?

    var snapshot: TelegramMediaEditorSnapshot {
        TelegramMediaEditorSnapshot(strokes: strokes, overlays: overlays)
    }

    var canUndo: Bool { !undoHistory.isEmpty }
    var canRedo: Bool { !redoHistory.isEmpty }

    var selectedOverlay: TelegramMediaOverlay? {
        guard let selectedOverlayID else { return nil }
        return overlays.first { $0.id == selectedOverlayID }
    }

    var selectedScale: Double {
        get { selectedOverlay?.scale ?? 1 }
        set { scaleSelected(to: newValue) }
    }

    var selectedRotationDegrees: Double {
        get { selectedOverlay?.rotationDegrees ?? 0 }
        set { rotateSelected(to: newValue) }
    }

    var selectedStartTime: Double {
        get { selectedOverlay?.startTime ?? 0 }
        set { setSelectedStartTime(newValue) }
    }

    var selectedEndTime: Double {
        get { min(selectedOverlay?.endTime ?? timelineDuration, timelineDuration) }
        set { setSelectedEndTime(newValue) }
    }

    func addStroke(points: [TelegramEditorPoint]) {
        guard !points.isEmpty else { return }
        recordMutation()
        strokes.append(.init(points: points, color: TelegramEditorColor(brushColor), width: brushWidth))
    }

    func addText(_ text: String) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        addOverlay(content: .text(value))
    }

    func addEmoji(_ emoji: String) {
        let value = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        addOverlay(content: .emoji(value))
    }

    func addSticker(_ sticker: TelegramStickerOverlay) {
        addOverlay(content: .sticker(sticker))
    }

    func select(_ id: UUID?) {
        selectedOverlayID = id
        if id != nil {
            tool = .select
        }
    }

    func beginInteraction() {
        interactionStart = interactionStart ?? snapshot
    }

    func moveSelected(to position: TelegramEditorPoint) {
        updateSelected { overlay in
            overlay.position = .init(
                x: min(max(position.x, 0), 1),
                y: min(max(position.y, 0), 1),
            )
        }
    }

    func scaleSelected(to scale: Double) {
        updateSelected { $0.scale = min(max(scale, 0.25), 4) }
    }

    func rotateSelected(to degrees: Double) {
        updateSelected { $0.rotationDegrees = min(max(degrees, -180), 180) }
    }

    func setSelectedStartTime(_ time: Double) {
        updateSelected { overlay in
            overlay.startTime = min(max(time, 0), max(0, overlay.endTime - 0.1))
        }
    }

    func setSelectedEndTime(_ time: Double) {
        updateSelected { overlay in
            overlay.endTime = min(max(time, overlay.startTime + 0.1), timelineDuration)
        }
    }

    func endInteraction() {
        guard let interactionStart else { return }
        self.interactionStart = nil
        guard interactionStart != snapshot else { return }
        undoHistory.append(interactionStart)
        trimHistory()
        redoHistory.removeAll()
    }

    func cancelInteraction() {
        guard let interactionStart else { return }
        restore(interactionStart)
        self.interactionStart = nil
    }

    func deleteSelected() {
        guard let selectedOverlayID,
              let index = overlays.firstIndex(where: { $0.id == selectedOverlayID })
        else { return }
        recordMutation()
        overlays.remove(at: index)
        self.selectedOverlayID = nil
    }

    func duplicateSelected() {
        guard var overlay = selectedOverlay else { return }
        recordMutation()
        overlay = TelegramMediaOverlay(
            content: overlay.content,
            position: .init(
                x: min(overlay.position.x + 0.05, 1),
                y: min(overlay.position.y + 0.05, 1),
            ),
            scale: overlay.scale,
            rotationDegrees: overlay.rotationDegrees,
            startTime: overlay.startTime,
            endTime: overlay.endTime,
        )
        overlays.append(overlay)
        selectedOverlayID = overlay.id
    }

    func bringSelectedForward() {
        guard let selectedOverlayID,
              let index = overlays.firstIndex(where: { $0.id == selectedOverlayID }),
              index < overlays.index(before: overlays.endIndex)
        else { return }
        recordMutation()
        overlays.swapAt(index, overlays.index(after: index))
    }

    func undo() {
        guard let previous = undoHistory.popLast() else { return }
        redoHistory.append(snapshot)
        restore(previous)
    }

    func redo() {
        guard let next = redoHistory.popLast() else { return }
        undoHistory.append(snapshot)
        restore(next)
    }

    // MARK: Private

    private static let maximumHistoryCount = 50

    private var undoHistory = [TelegramMediaEditorSnapshot]()
    private var redoHistory = [TelegramMediaEditorSnapshot]()
    private var interactionStart: TelegramMediaEditorSnapshot?

    private func addOverlay(content: TelegramMediaOverlayContent) {
        recordMutation()
        let overlay = TelegramMediaOverlay(
            content: content,
            endTime: timelineDuration > 0 ? timelineDuration : .greatestFiniteMagnitude,
        )
        overlays.append(overlay)
        selectedOverlayID = overlay.id
        tool = .select
    }

    private func updateSelected(_ update: (inout TelegramMediaOverlay) -> Void) {
        guard let selectedOverlayID,
              let index = overlays.firstIndex(where: { $0.id == selectedOverlayID })
        else { return }
        update(&overlays[index])
    }

    private func recordMutation() {
        undoHistory.append(snapshot)
        trimHistory()
        redoHistory.removeAll()
    }

    private func trimHistory() {
        if undoHistory.count > Self.maximumHistoryCount {
            undoHistory.removeFirst(undoHistory.count - Self.maximumHistoryCount)
        }
    }

    private func restore(_ snapshot: TelegramMediaEditorSnapshot) {
        strokes = snapshot.strokes
        overlays = snapshot.overlays
        if let selectedOverlayID, !overlays.contains(where: { $0.id == selectedOverlayID }) {
            self.selectedOverlayID = nil
        }
    }
}
