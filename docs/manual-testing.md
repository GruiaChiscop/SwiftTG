# Manual Testing Checklist

## Deferred

### Pasted attachments

- On macOS, copy one image in Finder and paste into the message field. Confirm it
  appears in the photo preview and that the path is not inserted as message text.
- Repeat with a document, multiple files, a screenshot copied as bitmap data, a
  quoted path containing spaces, and a valid path copied as plain text.
- Paste ordinary text, an HTTPS link, and a nonexistent path. Confirm all remain
  text. In edit mode, confirm even a valid path remains editable text.
- On iOS, copy an image and a document from an app that provides clipboard file
  URLs. Confirm they enter the corresponding attachment preview and can be sent.
- With VoiceOver, confirm the attachment announcement occurs once and each staged
  item and its Remove button are reachable before sending.

### Shared media

- Open **Shared Media** from an iOS conversation and from macOS Chat Info. Confirm
  Media, Files, Links, Music, and Voice return results from the entire chat rather
  than only the currently loaded history window.
- Switch repeatedly between categories and confirm already loaded results remain
  cached while each category paginates independently.
- On iOS, confirm the horizontal tab strip remains usable with VoiceOver and large
  Dynamic Type sizes and announces the selected category.
- On macOS, use Up/Down in Files, Links, Music, and Voice. Confirm selection moves
  without opening an item. Confirm Return, Space, and double-click activate only
  the selected row.
- Activate a link and confirm it opens in the default browser. Activate another
  item and confirm BetterTG returns to and focuses the source message.
- Verify empty, loading, retry, and final-page states in each category.

### Clear chat history

- From the chat list on iOS and macOS, confirm **Clear History** opens a dialog
  with **Cancel** and only the deletion scopes allowed by TDLib.
- In an expendable private chat, clear only for yourself and verify all messages
  disappear while the empty conversation remains in the chat list.
- Where Telegram permits it, repeat with **Clear for everyone** and verify the
  history disappears for the other participant as well.
- Confirm **Delete** remains a separate action and still removes the conversation
  from the chat list.
- For a group and a channel where the account is a member, verify both the
  VoiceOver actions and context menu contain **Archive**, **Clear History**, and
  the correctly named **Leave Group** or **Leave Channel** action.
- Cancel the Leave confirmation once, then confirm it and verify the account
  leaves the community and the conversation disappears from the chat list.

### macOS login while preserving the current session

- In the BetterTGMac scheme, open **Run > Arguments** and add the launch argument
  `-BetterTGLoginTestSession`.
- Run the app. Debug builds use `td-login-test` instead of the normal `td` TDLib
  directory, so the existing authorized session remains untouched.
- Verify country selection, manual calling-code entry, automatic country/flag
  detection, focus transfer to the phone-number field, and the SMS warning.
- Avoid repeatedly submitting a real phone number because Telegram limits login
  attempts. Remove the launch argument to return to the normal session.
- From another Telegram client, terminate the BetterTG macOS session. Confirm
  BetterTG replaces the workspace with a **Telegram Session Ended** explanation,
  waits for TDLib to close, and then exposes **Reauthenticate**.
- Activate **Reauthenticate** and confirm a fresh TDLib client reaches the phone
  entry screen without showing stale chats or messages.

### Audio streaming

- On iOS, activate one cached and one never-downloaded voice message. Confirm the
  cached message starts immediately and the other starts automatically after its
  download, without requiring a second activation or moving VoiceOver focus.
- Start an audio message that has not been downloaded and confirm playback begins
  after buffering only part of the file.
- Seek forward before the complete file has downloaded.
- Switch rapidly between audio messages and between an audio message and a voice
  note.
- Leave the source conversation while music is playing and confirm the persistent
  player remains available. Verify Previous, Next, automatic advancement, replay
  after completion, and Close Player on both iOS and macOS.
- Verify buffering, failure, cancellation, and full-download fallback behavior on
  a slow or interrupted connection.
- Confirm VoiceOver focus and playback progress remain stable.

### Apple push notifications

- In Apple Developer, enable **Push Notifications** for both
  `com.gruiachiscop.BetterTG` and `com.gruiachiscop.BetterTGMac`, then regenerate
  or refresh their development provisioning profiles.
- In the Telegram application settings associated with BetterTG's `api_id`,
  configure the APNs certificate used by Telegram's provider service. The
  certificate/topic must match the bundle identifier receiving the token; verify
  the separate macOS bundle identifier is supported before treating token
  registration as complete.
- Run each app with signing enabled and confirm APNs registration succeeds without
  the `didFailToRegisterForRemoteNotificationsWithError` log.
- With the macOS window hidden in the menu bar, send messages to a private chat,
  group, muted group, channel, and muted channel. Confirm TDLib applies the same
  mute and preview rules as it does for live `updateNotificationGroup` events.
- Confirm tapping a macOS notification opens BetterTG and activates the relevant
  conversation when TDLib provides its chat identifier.
- Test a Debug build against APNs sandbox and an archived/TestFlight or release
  build against APNs production.
- Quit macOS BetterTG completely and confirm the documented platform limitation:
  full notification processing requires the app to remain running; macOS only
  supports app-icon badging for this APNs path while the app isn't running.

### macOS AppKit accessibility

- Move VoiceOver from the composer into the message list, then use Up/Down.
  Confirm focus follows one message at a time and VoiceOver does not report
  multiple selected rows. Confirm returning to the composer leaves arrow-key
  handling with the text field rather than the native message table.
- Focus a message containing selectable text or links and use Up/Down. Confirm
  navigation continues in the message list; then confirm pointer link activation
  and text selection still work.
- After selecting ordinary and interactive messages with Up/Down, press
  `VO-Shift-M`. Confirm the same message context menu opens in every case.
- For a message with links, reactions, or both, interact with its accessibility
  group and confirm each link and the Reactions button are available. Confirm the
  message label does not repeat the reactions.
- Load older history at the top and confirm the visible anchor does not jump.
- Use Scroll to Bottom, search-result navigation, and Go to Quoted Message and
  confirm the destination row becomes selected and receives keyboard focus.
- Keep reaction details on the Reactions button rather than duplicating them in
  the parent message label.

### iOS video messages

- Open a standalone video message with VoiceOver and confirm the message exposes the `Play Video` action.
- Confirm the thumbnail and duration are shown and announced without making VoiceOver navigation sluggish.
- Confirm the video downloads, opens, starts playback, and stops when the viewer is dismissed.
- Confirm sharing becomes available after the video has downloaded.
- Test an album containing both photos and videos, including page navigation and sharing the selected item.
- Verify video captions in the message, chat-list preview, reply preview, Copy action, and Edit action.
