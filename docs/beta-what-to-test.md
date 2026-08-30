# What to Test

Video calls

- One-to-one video call: the other person's video appears, tracks their audio,
  and keeps updating rather than freezing on the first frame.
- Your own camera preview is correct; front/back switch and camera off/on work
  mid-call.
- Rotating the device reflows both video views without stretching, bad cropping,
  or stray black bars.
- Behaviour on Wi-Fi, on mobile data, and across a brief network drop.

## Conferences (encrypted group calls)

- Create one from a one-to-one call, add people, and confirm everyone sees and
  hears each other.
- Join from an invitation without getting stuck on "connecting".
- Audio and video routing stays correct as people join and leave.
- Leaving, rejoining, and ending the conference each return the UI to normal.

## Group calls and video chats

- Create and join a group voice chat: speak, mute and unmute, raise hand, leave.
- Join a channel live stream and confirm playback starts and stays in sync.
- Flag anything with no audio, no connection, or the wrong participant state.

## Audio calls

- Place, receive, decline, and miss calls.
- Answer from the lock screen (CallKit).
- Switch audio route: speaker, earpiece, Bluetooth.

## Call history

- The Recent Calls list shows the right people, call direction, missed and
  outgoing status, video and conference markers, and both the date and the time.
- The detail screen (ⓘ) opens and its actions work.

## Screen sharing

- Start and stop during a call and during a conference. The other side sees the
  screen, and sharing stops the instant you end it.

## Picture in Picture

- Send a video call to PiP, use other apps, then return. The call UI restores
  with no blank or duplicated call screen.

## Stickers

- Create a set, then add, edit, reorder, and remove stickers.
- Send stickers into a chat; they render at the right size and animate where
  applicable.

## Video messages (round video notes)

- Record and send one: it plays inline, loops, shows the correct thumbnail, and
  keeps audio in sync.
- Its reply preview and chat-list preview look right.

## GIFs

- Search for a GIF and send it; save a GIF to favourites and send a saved one.
- It plays inline, loops, and shows the right preview in the chat and in the
  picker.

## Live location

- Not tested properly yet. Share your live location in a chat and confirm the
  other side sees it update as you move, and that it stops at the chosen expiry
  or when you stop it by hand.
- Leave the app and keep moving: the shared location should keep updating, and a
  bar in the app should show sharing is active.

## Chat folders

- Create, rename, and delete folders.
- Add and remove chats, and reorder folders.
- The chat-list folder tabs match each folder's contents and update when chats
  move between folders.

## Two-step verification (2FA)

- Set a password, add and verify a recovery email, then change and remove the
  password.
- Sign in with 2FA enabled: the password screen shows a "Password" field with
  the hint on its own line (matches macOS).
- "Forgot Password?" with a recovery email on file: a code is sent there;
  entering it plus a new password signs you in.
- "Forgot Password?" with no recovery email: the "Reset Account?" alert appears,
  and confirming deletes the account and all its messages.
- Check the same flow on macOS.

## Verification code screen

- The screen says where the code was sent; the resend button counts down, then
  works, and its label reflects the next delivery method.
- "Change Number" returns to the phone step with the number kept.
- Continue is disabled with an empty phone number or empty code; SMS autofill
  offers the code above the keyboard.

## Account and safety

- Log Out (Settings → You): signs out and returns to the phone-number screen.
- Delete My Account (Settings → Privacy and Security): the confirmation appears;
  with two-step verification on it asks for the password; on success the app
  returns to login.
- Report a message (message menu → Report) and report a chat or user (Chat Info
  → Report): the reason list loads from the server, sub-options and the details
  step work, and it ends with a confirmation. Check on macOS too.

## Proxy

- Add an MTProto proxy and a SOCKS5 proxy, enable and disable each, and confirm
  the connection status reflects the change.
- Confirm chats, media, and calls still work whilst a proxy is enabled.

## Layout

- Screens lay out correctly across device sizes, orientations, and large Dynamic
  Type: nothing clipped, overlapping, or pushed off screen.
- The message list renders correctly: bubbles sized to their content, in order,
  aligned to the correct side, no overlap or clipping, and scrolling stays
  smooth with no jumps.
- Watch the call screens, chat view, settings, and sticker screens in
  particular.

## Accessibility

- Full pass with VoiceOver: every control reachable and labelled, sensible focus
  order, no focus traps.
- Report any wrong or missing labels, especially on the call screens, message
  rows, and notifications.
- Check with Reduce Motion enabled.

## Notifications

- Push notifications arrive, open the right chat, and clear from Notification
  Center when that chat is opened.
- Tapping a notification whilst another chat is open returns to the chat list on
  Back, not to the previous chat.
- On launch with a backlog from several chats: no burst of in-app banners and
  sounds — at most one, for the newest message.
- Notification sounds, banner appearance, and in-app banners while the app is
  foregrounded.

## Known issues

- App size on device grows over time because media, mainly voice messages, is
  downloaded and cached. It can be reduced from Settings → Data and Storage →
  Clear Cache, but the size figures take a moment to calculate first.

---

## Internal to-do (not for testers)

- Data and Storage: show a "Calculating…" state for the cache and database
  figures while `getStorageStatisticsFast` runs, and reflect ongoing media
  downloading if we can detect it, so the screen does not look stuck on stale or
  zero numbers.
