// MacMessageAccessibilityBridge.swift

import AppKit

// MARK: - MacMessageAccessibilityDescriptor

/// One accessible unit inside a message row - the message itself, its reactions, or its link
/// preview - handed from SwiftUI (which still computes every label and action, unchanged) to the
/// AppKit layer that presents it to VoiceOver. See `MacMessageAccessibilityBridge` for why this
/// indirection exists.
struct MacMessageAccessibilityDescriptor {
    let role: NSAccessibility.Role
    let label: String
    let value: String
    let isEnabled: Bool
    let activate: (@MainActor () -> Void)?
    let customActions: [(title: String, action: @MainActor () -> Void)]

    init(
        role: NSAccessibility.Role,
        label: String,
        value: String = "",
        isEnabled: Bool = true,
        activate: (@MainActor () -> Void)? = nil,
        customActions: [(title: String, action: @MainActor () -> Void)] = [],
    ) {
        self.role = role
        self.label = label
        self.value = value
        self.isEnabled = isEnabled
        self.activate = activate
        self.customActions = customActions
    }
}

// MARK: - MacMessageAccessibilityBridge

/// `NSHostingView`'s own accessibility bridging turned out to be unreliable for VoiceOver's macOS
/// Interact command once a message row exposed more than one real child element: Interact would
/// read the reactions/link-preview elements correctly, then exit on its own instead of stopping
/// only on an explicit Stop Interacting, and arrow-key navigation between the children didn't
/// track reliably. Other developers hitting `NSHostingView` inserting its own opaque "AXHostingView"
/// wrapper node into the accessibility tree have reported the same class of symptom.
///
/// Apple's own accessible-table sample code (`AccessibilityUIExamples`) sidesteps that bridging
/// entirely for rows with real internal structure: the row reports its own children directly to
/// AppKit instead of relying on automatic view-tree discovery. This bridge is the SwiftUI-facing
/// half of that same approach - `MacMessageRow` keeps computing every label, value, and action
/// exactly as it already did (nothing here is duplicated or recomputed) and just hands the current
/// snapshot to whichever `HostedMessageCell` is hosting it; `MessageNSTableView.accessibilityRows()`
/// (see `MacMessageTableRowAccessibilityElement`) turns that snapshot into real
/// `NSAccessibilityElement` instances instead of leaving it to `NSTableView`/`NSHostingView` to
/// expose them.
@MainActor
final class MacMessageAccessibilityBridge {
    /// The view whose accessible structure this bridge describes - `HostedMessageCell` sets this to
    /// itself right after creating the bridge. Changing `primary`/`children` posts a notification on
    /// this view, since none of the five earlier attempts at exposing extra children ever told
    /// VoiceOver the structure had changed: `MacMessageRow`'s `.task(id:)` populates this bridge
    /// *after* the row/cell view already exists and may already have been scanned once, and without
    /// an explicit notification, VoiceOver has no reason to ever re-fetch and notice the update - a
    /// documented AppKit requirement ("make sure you are posting any relevant notifications as your
    /// control's state changes") that every prior attempt here missed regardless of which level
    /// (SwiftUI, cell, row, table) it tried to attach children at.
    weak var owner: NSView?

    /// The message's own label/value/actions, presented directly on `HostedMessageCell` (not as a
    /// child) - so a plain up/down arrow read still announces the message the way it always did,
    /// instead of "empty cell": once the cell exposes `accessibilityChildren()` at all, VoiceOver
    /// stops summarizing it from an un-labeled, `isAccessibilityElement(false)` wrapper the way it
    /// did for the single combined SwiftUI element this replaced.
    private(set) var primary: MacMessageAccessibilityDescriptor?

    /// Reactions and/or a link preview - real `NSAccessibilityElement` children the cell reports
    /// alongside its own `primary` presentation, reachable via VoiceOver's Interact.
    private(set) var children: [MacMessageAccessibilityDescriptor] = []

    /// Silent counterpart to `update(primary:children:)` - cells are reused across rows while
    /// scrolling, and `Coordinator` clears a recycled cell's bridge before the new row's SwiftUI
    /// content has run its `.task` and called `update`, so the old row's accessibility content isn't
    /// shown mid-transition. Posting `.layoutChanged` for that transient, immediately-superseded
    /// state served no one and, across every row touched by a scroll, was enough traffic to make
    /// VoiceOver noticeably sluggish - notifications belong on genuine content arriving, not on
    /// clearing a cell that's about to be reused.
    func reset() {
        primary = nil
        children = []
        // A reused cell's next `update()` is a different message and must always be free to post,
        // even if that message's structural signature happens to coincide with whatever this cell
        // last reported.
        lastPostedSignature = nil
    }

    /// The one path that posts `.layoutChanged`, but only when the *structure* actually changed -
    /// `MacMessageRow`'s `.task(id:)` also re-runs for things that only affect the spoken label, like
    /// a playing voice message's elapsed time ticking every fraction of a second, and calls this every
    /// time to keep that label fresh. Posting a notification on every one of those would mean a
    /// `.layoutChanged` several times a second for as long as any voice/audio message keeps playing -
    /// exactly the kind of traffic that made VoiceOver sluggish before, just from a different source
    /// than the scroll-reuse case `reset()` fixed. Comparing against `lastPostedSignature` keeps data
    /// (`primary`/`children`, read fresh on every VoiceOver query regardless) up to date on every
    /// call while only notifying when reactions, a link, activation, or the custom-action count -
    /// things that change what Interact finds - actually changed.
    func update(primary: MacMessageAccessibilityDescriptor?, children: [MacMessageAccessibilityDescriptor]) {
        self.primary = primary
        self.children = children

        let signature = [
            String(children.count),
            String(primary?.customActions.count ?? 0),
            String(primary?.activate != nil),
            primary?.role.rawValue ?? "",
        ].joined(separator: "|")
        guard signature != lastPostedSignature else { return }
        lastPostedSignature = signature

        guard let owner else { return }
        NSAccessibility.post(element: owner, notification: .layoutChanged)
    }

    private var lastPostedSignature: String?
}

// MARK: - MacMessageAccessibilityChildElement

/// A synthetic per-descriptor accessibility node. Geometry is approximated to the hosting cell's
/// own frame rather than the descriptor's actual on-screen rect - precise per-element frames would
/// need their layout plumbed out of SwiftUI via `GeometryReader`, which is unrelated to what was
/// actually broken (Interact/arrow navigation, not the visual focus ring) and is a reasonable
/// follow-up rather than part of this fix.
/// Deliberately not `@MainActor`: `NSAccessibilityElement`'s override points aren't declared
/// `@MainActor` in the SDK (AppKit's accessibility machinery can in principle call them off the
/// main thread), and making this class `@MainActor` while overriding those nonisolated methods
/// only produces "sending self" diagnostics without adding real safety - `descriptor` itself is
/// plain data. The only actually actor-sensitive step is invoking `descriptor`'s closures, since
/// they touch `MacMessageRow`'s SwiftUI state; that step alone is wrapped in `assumeIsolated`,
/// documenting the assumption that - for this locally-hosted, non-cross-process view - the
/// accessibility server calls back on the same (main) thread it was asked from.
final class MacMessageAccessibilityChildElement: NSAccessibilityElement {
    // MARK: Lifecycle

    /// `frame` is taken as a plain `NSRect` rather than read from `parent` here, since reading
    /// `NSView.accessibilityFrame()` is itself main-actor-isolated in the SDK and this initializer
    /// isn't - the caller (already on the main actor) computes it instead.
    init(descriptor: MacMessageAccessibilityDescriptor, in parent: NSView, frame: NSRect) {
        self.descriptor = descriptor
        super.init()
        setAccessibilityParent(parent)
        setAccessibilityRole(descriptor.role)
        setAccessibilityLabel(descriptor.label)
        if !descriptor.value.isEmpty {
            setAccessibilityValue(descriptor.value)
        }
        setAccessibilityEnabled(descriptor.isEnabled)
        setAccessibilityFrame(frame)
    }

    // MARK: Internal

    let descriptor: MacMessageAccessibilityDescriptor

    override func accessibilityPerformPress() -> Bool {
        guard let activate = descriptor.activate else { return false }
        MainActor.assumeIsolated {
            activate()
        }
        return true
    }

    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        guard !descriptor.customActions.isEmpty else { return nil }
        return descriptor.customActions.map { item in
            let action = MainActorClosureBox(run: item.action)
            return NSAccessibilityCustomAction(name: item.title) {
                MainActor.assumeIsolated {
                    action.run()
                }
                return true
            }
        }
    }
}

/// `NSAccessibilityCustomAction.init(name:handler:)` requires a `Sendable` handler, but the
/// `@MainActor` closures this bridge carries capture `MacMessageRow`'s SwiftUI state and can't be
/// made genuinely `Sendable`. `@unchecked` is safe here specifically because `run` is never invoked
/// except inside `MainActor.assumeIsolated` immediately above - the same same-thread assumption
/// documented on `MacMessageAccessibilityChildElement`, not a blanket claim about the closure itself.
struct MainActorClosureBox: @unchecked Sendable {
    let run: @MainActor () -> Void
}

// MARK: - MacMessageTableRowAccessibilityElement

/// Reports a table row's accessible structure directly to `MessageNSTableView.accessibilityRows()`,
/// replacing `NSTableView`'s own default per-row exposure for message rows.
///
/// Four earlier attempts overrode `accessibilityChildren()` at progressively different levels -
/// SwiftUI's own `.accessibilityElement(children:)`, `HostedMessageCell`, then `MessageTableRowView`
/// - and all failed identically: VoiceOver's Interact never surfaced the extra children, even once
/// they were correctly retained. Apple's own accessible-table sample code never touches a real
/// `NSTableCellView`/`NSTableRowView` at all - only fully custom, hand-drawn `NSView` controls -
/// which points at `NSTableView` simply not consulting those views' own overrides for what a row's
/// children are; it most likely builds its default `accessibilityRows()` answer from its own
/// column/row bookkeeping instead of asking each row/cell view. Overriding `accessibilityRows()` on
/// the table itself replaces that bookkeeping-driven answer at its source, rather than trying to
/// patch a leaf `NSTableView` never asks about the same way it already asks the leaf its own
/// label/value/actions.
final class MacMessageTableRowAccessibilityElement: NSAccessibilityElement, NSAccessibilityRow {
    // MARK: Lifecycle

    init(cell: NSView, in table: NSTableView) {
        self.cell = cell
        super.init()
        setAccessibilityParent(table)
        setAccessibilityRole(.row)
    }

    // MARK: Internal

    private(set) var extraElements: [MacMessageAccessibilityChildElement] = []

    func update(index: Int, extraDescriptors: [MacMessageAccessibilityDescriptor], frame: NSRect) {
        setAccessibilityIndex(index)
        extraElements = extraDescriptors.map { MacMessageAccessibilityChildElement(descriptor: $0, in: cell, frame: frame) }
    }

    override func accessibilityChildren() -> [Any]? {
        [cell] + extraElements
    }

    /// `NSAccessibilityElement`'s own `accessibilityIdentifier()` returns `String?`, matching the
    /// general `NSAccessibility` informal protocol - but `NSAccessibilityRow`'s inherited
    /// `NSAccessibilityElementProtocol` requires a non-optional `String`. Without this override the
    /// two disagree and the class fails to compile as conforming to `NSAccessibilityRow` at all.
    override func accessibilityIdentifier() -> String {
        identifier
    }

    // MARK: Private

    private let cell: NSView
    private let identifier = UUID().uuidString
}
