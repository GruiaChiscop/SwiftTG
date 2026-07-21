# BetterTG Project Status

Last updated: 18 July 2026

This document records the current implementation state and the work that still
needs runtime verification. It is intended to be updated as the iOS and macOS
clients evolve.

## Architecture and shared infrastructure

- Telegram access is routed through the shared `TelegramService` abstraction and
  the session-backed implementation instead of being initiated directly by most
  views.
- Shared stores handle chat-list and message updates, with focused render state
  on iOS to avoid rebuilding every visible message for unrelated TDLib events.
- Message metadata, editing, reactions, service messages, audio playback, and
  other cross-platform behavior have been moved into shared components where
  practical.
- Outgoing text, media captions, voice-note captions, and edited messages use
  TDLib's text-entity detector on both platforms. Multiple URLs, email addresses,
  mentions, hashtags, cashtags, bot commands, and bank-card numbers are combined
  with explicit rich-text entities without replacing custom text links.
- Tests cover important message-store, metadata, and render-store behavior.
- Expensive test runs are intentionally deferred during normal iteration because
  they generate significantly more heat than incremental Xcode builds.

## Accessibility and message behavior

- VoiceOver activation of voice messages starts playback without reloading the
  window or moving focus to the Back button.
- Message accessibility labels include author, date, delivery status, edited
  state, reply context, quoted-message excerpts, media details, and voice-message
  duration/progress where applicable.
- Message actions are ordered and conditionally exposed according to message,
  chat, ownership, and permission state. Invalid actions such as pinning without
  permission or navigating to a missing quoted message are hidden.
- Chat-list actions include read/unread, mute, pin/archive, and a consolidated
  deletion dialog with cancellation.
- Reply and quoted-message navigation, forwarding metadata, reactions, service
  messages, date headings, unread headings, and search result sections have been
  added or refined.
- Long-message labels preserve their original newlines instead of rewriting the
  message text for accessibility.
- URL, text-URL, email, phone-number, and mention entities are interactive in
  message text and media captions. The message keeps its single accessibility
  label; an outer group exposes links and Reactions as sibling controls after one
  VoiceOver interaction, instead of listing links as custom message actions or
  nesting another group inside the message.
- macOS keyboard focus follows VoiceOver navigation into the chat and message
  tables without opening chats merely because the arrow-key highlight changed.

## iOS and macOS clients

- The macOS client has a split workspace with a chat table and the explicitly
  opened conversation. Moving through the chat table does not automatically open
  or mark conversations as read.
- macOS message loading opens near the latest message and uses bounded,
  incremental history loading. A scroll-to-bottom command is available.
- Search results distinguish chats from messages and reuse the normal chat-row
  information.
- Chat and message presentation includes group/channel indicators, sender names,
  timestamps, delivery status, edited state, replies, documents, media, reactions,
  and relevant context-menu actions on both platforms where implemented.
- The macOS application can remain in the menu bar for notification polling. Quit
  presents the choice between keeping the application active in the menu bar and
  terminating it.
- Push notification support is enabled for both Apple targets. iOS and macOS
  share TDLib authorization coordination, Apple device-token registration, and
  push-payload processing. macOS uses the platform-specific
  `com.apple.developer.aps-environment` entitlement and forwards AppKit delegate
  callbacks into the shared registration component. The existing menu-bar and
  TDLib local-notification path remains available. Signed APNs delivery still
  needs end-to-end validation for both bundle identifiers.
- Country selection now uses the TDLib country list on both iOS and macOS. The
  shared country model generates the corresponding flag emoji from each ISO
  country code. macOS has separate editable calling-code and subscriber-number
  fields, detects the country from a manually entered prefix, and transfers focus
  to the number field when the calling code is complete. Selecting a country also
  fills its prefix and focuses the number field.
- Both login screens warn that Telegram may be unable to deliver SMS/call login
  codes to third-party apps. Debug macOS builds support the
  `-BetterTGLoginTestSession` launch argument for exercising login with a separate
  TDLib database while preserving the normal authorized session.
- macOS detects unexpected TDLib `loggingOut`, `closing`, and `closed`
  authorization states, explains that the Telegram session ended, and offers
  reauthentication after the old client has fully closed. Reauthentication uses
  a fresh session object and clears stale UI work while retaining the TDLib data
  directory.
- Both composers recognize copied file URLs as attachments. Copied images use the
  existing photo preview and other files use the document list. macOS additionally
  recognizes pasted textual paths only when every path resolves to an existing
  file, and accepts bitmap clipboard content by staging it as a temporary PNG.
  Ordinary text, web URLs, and paths pasted while editing a message remain text.
- Message send/receive and other relevant service sounds are included.
- macOS local notifications are driven by TDLib `updateNotificationGroup` events
  rather than raw incoming-message events. This lets TDLib apply per-chat and
  inherited mute settings consistently for private chats, groups, and channels,
  while also respecting preview, silent-message, sound, removal, and age data.
  This notification path, including muted groups and channels, has been verified
  at runtime and is no longer on the deferred manual-testing list.
- Selecting the conversation header on macOS opens Chat Info. The screen exposes
  the information TDLib currently makes available for the chat: identity and
  presence, biography or description, usernames, phone number, birthdate, bot
  privacy policy, member and moderation counts, common-group count,
  notification status, a short member preview for small groups, and a separate
  paginated member list with server-side search for larger groups.
  Available actions include mute/unmute, open a member conversation, block or
  unblock a private user, leave a group or channel, clear chat history without
  removing the conversation, and delete the chat. Clear History is also exposed
  from the iOS and macOS chat-list actions; iOS additionally exposes it from the
  open conversation's actions menu. Group and channel chat-list menus distinguish
  membership actions from history deletion: members can leave, creators can
  delete the community when TDLib permits it, and Archive and Clear History stay
  separate actions.
- TODO: Bring iOS Chat Info to feature parity with macOS, including complete
  identity/details, member and moderation information, notification controls,
  member browsing, common groups, and the corresponding chat-management actions.
- Telegram-style shared-media browsing now uses a shared, paginated
  `searchChatMessages` source rather than synthesizing results from the currently
  loaded message window. Media, Files, Links, Music, and Voice keep independent
  cursors, cached results, and loading/error state. iOS presents horizontally scrollable tabs;
  macOS uses a segmented picker. The macOS list categories use a native AppKit
  table: arrows only move selection, while Return, Space, or double-click activates
  the selected item. Media uses an adaptive thumbnail grid on both platforms.

## Platform code sharing

- Chat-list action rules and titles, mute presets, and reaction/pin/delete message
  commands are now shared by iOS and macOS through `BetterTGShared`. Country and
  phone-number normalization, service-sound throttling, and text/photo/document
  sending semantics are shared as well. Voice-note staging, waveform packing,
  TDLib content construction, upload actions, and sending now use the same shared
  implementation on both platforms.
- Voice recording follows Telegram iOS's in-memory incremental Ogg/Opus encoding
  model. Completed recordings are staged on disk only because TDLib requires an
  input-file path. Staging files are removed after `updateMessageSendSucceeded`;
  failed sends retain their source for Retry, and abandoned files expire after
  24 hours.
- The remaining duplication and safe extraction order are tracked in
  `docs/platform-code-sharing.md`. UI composition, accessibility focus,
  notification integration, and OS media controls intentionally remain
  platform-specific.

## Audio player

- Audio messages no longer start a full download merely because their row is
  visible.
- `TDLibAudioResourceLoader` supplies byte ranges requested by `AVPlayer`, using
  TDLib partial-file downloads.
- Files already available locally are played directly.
- A complete-download fallback is used when range streaming cannot start or is
  unsupported for a particular file.
- The shared player exposes playback, buffering, elapsed-time, downloaded-byte,
  total-size, completion, and error state.
- Switching to another audio message stops the current item and starts the newly
  selected item. Audio messages and voice notes also stop one another.
- Audio messages now retain the ordered set of music tracks already loaded in
  their conversation. Playback advances automatically within that bounded list,
  and Previous and Next are available from a persistent, accessible player on
  both iOS and macOS. The player remains available after leaving the source chat
  and can be dismissed explicitly.
- iOS and macOS builds compile successfully with the new player.

### Audio runtime verification still required

- Start an audio message that has never been downloaded and confirm that playback
  begins after a short buffer rather than after the whole file arrives.
- Seek forward while only part of the file is available.
- Switch rapidly between two audio messages and between an audio message and a
  voice note.
- Confirm Previous, Next, automatic advancement, replay after reaching the end,
  and closing the persistent player work on both platforms.
- Test slow connectivity, interrupted connectivity, cancellation, and the
  complete-download fallback.
- Confirm playback progress and VoiceOver announcements remain stable throughout.
- Loading additional playlist pages, repeat, shuffle, and system Now Playing
  integration are not implemented yet.

## AppKit note

AppKit remains an intentional macOS dependency. It is currently used where native
macOS window lifecycle, menu-bar behavior, tables, focus coordination, context
menus, and accessibility interoperation cannot be expressed reliably enough by
the shared SwiftUI layer alone. It should not be removed merely to make the code
appear fully cross-platform; AppKit-specific code should instead stay isolated in
small macOS-only components.

The macOS conversation history uses an isolated AppKit `NSTableView`. Native table
selection and first-responder handling own Up/Down navigation, while hosted
SwiftUI rows retain the existing message presentation and actions. The table also
preserves the visible anchor when older history is inserted and handles initial,
search-result, quoted-message, and latest-message positioning. The AppKit text
view used for selectable formatted text forwards plain Up/Down events to its
enclosing table, while text selection and link activation remain available.
Table, row, and cell accessibility menu handlers route `VO-Shift-M` to the
focused SwiftUI message's existing context menu.

Messages containing links or reactions expose the original SwiftUI accessibility
group inside the native table row. The group owns the message activation action,
its links, and the **Reactions** button. AppKit is responsible only for table
selection, keyboard navigation, scrolling, and context-menu routing.

## Next work

- Runtime-test and refine the range-based audio player.
- Runtime-test VoiceOver and arrow-key navigation in the AppKit message table,
  including links, reactions, context menus, quoted-message jumps, and history
  pagination.
- Complete the audio playlist/global-player features if desired.
- Continue synchronizing missing iOS and macOS Telegram functionality without
  coupling TDLib state directly to platform views.
- Perform the deferred iOS video-message and APNs end-to-end checks documented in
  the manual testing checklist.
