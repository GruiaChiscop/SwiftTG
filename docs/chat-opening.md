# Chat opening and VoiceOver

`ChatOpeningCoordinator` owns the initial presentation plan. `ChatView` selects it after
`ChatVM.initialMessagesLoaded`; the view does not treat submitting a scroll command as completion.

## Sequence

1. `ChatVM` finishes the initial history fetch and renders the loaded message window. A cached
   snapshot alone cannot finish this stage. Opening an ordinary chat requests its latest window,
   even when older cached rows are already available.
2. The opening coordinator captures the scroll destination, unread anchor, and focus target.
   Later history insertions and read-counter updates do not select a different opening plan.
3. `ChatHistoryNavigator.positionInitially` retains the request until the table can acknowledge
   it. `performInitial` requires appearance in a window, nonempty viewport geometry, completion
   of snapshot application, and a visible target cell after resolving estimated row heights.
   Empty histories can acknowledge bottom positioning without a message cell.
4. The acknowledgement advances the coordinator to `ready` on the main queue after the current
   UIKit callback. Only this state enables read reporting, pagination, and the initial focus
   request. Read reporting also requires an active, visible, non-preview conversation.
5. The native focus controller waits for a visible target and navigation completion. Before
   posting unread-header focus, it checks that the current snapshot still assigns that cell to
   the requested unread header. Reconfiguration does not repeat an already delivered request.

`ready` means the table has acknowledged the initial destination. It does not mean VoiceOver has
confirmed receiving focus, or that no future layout change can occur. Real VoiceOver navigation
must still be checked on a device.

## Cancellation and ownership

- Leaving invalidates deferred acknowledgements and pending initial navigation. A completed
  opening stays completed; a paused opening can resume positioning without reclaiming focus.
- Explicit navigation supersedes a pending initial request. The old opening cannot restore its
  destination or claim focus afterward.
- Subsequent snapshots and banner changes update their own content; they do not create a new
  opening plan. Do not add independent initial-focus timers or `Task.yield()` chains in rows.
- The unread header's accessibility element belongs to the native table cell. Its SwiftUI
  content is visual only. Message labels remain complete when the visual text is truncated.
- Marking the initial unread range read is separate from visible-row view reporting. Ordinary
  chat openings use the latest message captured at entry; previews, explicit message links,
  and topic-scoped histories do not trigger this whole-chat receipt.

## Regression coverage

`ChatOpeningCoordinatorTests` varies the order of history, geometry, and appearance, and covers
cancellation, resumption, superseding navigation, and focus selection. The table-controller tests
exercise the acknowledgement against actual UIKit cells, including empty conversations.
`VoiceOverFocusControllerTests` cover deferred delivery, transitions, cancellation, and a snapshot
starting before delivery. `ChatInitialReadTests` and `ChatBannerLayoutTests` cover unread receipts,
cache loading, and translation-banner height.

On a physical device with VoiceOver, check unread and already-read chats, an empty writable chat,
long messages, translation/pinned banners arriving during opening, quick Back and reopening, and
an explicit jump to another message. Confirm both cursor destination and the unread count after
returning to the chat list. These checks complement the automated tests.
