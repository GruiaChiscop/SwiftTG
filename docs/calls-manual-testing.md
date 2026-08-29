# Calls Manual Testing Checklist

Last updated: 29 August 2026

This checklist covers the current BetterTG call implementation on iOS. It is
intended for a real-device test session with a second Telegram account. Record
bugs separately and include the devices, iOS versions, network conditions, and
the exact step that failed.

## Test setup

- [ ] Use two iPhones with separate Telegram accounts and BetterTG installed on
  at least one device.
- [ ] Keep a third account or device available for conference tests.
- [ ] Allow microphone, camera, notification, and screen-recording permissions
  when requested.
- [ ] Confirm both devices can make ordinary Telegram calls before testing edge
  cases.
- [ ] Use an expendable group or conference where ending the call for everyone
  is safe.
- [ ] Record the BetterTG commit, build configuration, device models, and iOS
  versions used for the session.

## Private audio calls

### Chat Info and call history

- [ ] Open Chat Info for a regular user who accepts calls and confirm Call and
  Video appear alongside Search without duplicating the existing Mute or Unmute
  control from the Notifications section.
- [ ] Confirm Call and Video are absent for Saved Messages, bots, deleted users,
  support accounts, and users whose privacy settings do not allow the relevant
  call type.
- [ ] Start an audio call and a video call from Chat Info.
- [ ] Deny microphone or camera permission and confirm the corresponding Settings
  action is presented from Chat Info.
- [ ] Confirm completed history entries distinguish Incoming Call, Outgoing Call,
  Incoming Video Call, and Outgoing Video Call.
- [ ] Confirm unsuccessful entries distinguish Missed Call or Missed Video Call
  for incoming calls and Cancelled Call or Cancelled Video Call for outgoing
  calls.
- [ ] Confirm disconnected calls use Telegram-iOS's Cancelled wording.
- [ ] Confirm calls longer than one second show their duration, while zero- and
  one-second calls show only the message time.
- [ ] Confirm successful direction arrows are green and unsuccessful arrows are
  red, with the correct incoming or outgoing direction.
- [ ] Activate an audio or video call bubble and confirm it calls the same peer
  using the original media type.
- [ ] With VoiceOver, confirm the call type, direction, result, duration, date,
  and the call bubble's button behavior are understandable without duplicated
  announcements.
- [ ] Confirm the chat-list preview, conversation search result, and
  pinned-message preview no longer reduce every call to the generic word Call.

### Outgoing call

- [ ] Start an audio call from a private conversation.
- [ ] Confirm the outgoing, ringing, connecting, and active states are shown in
  the correct order.
- [ ] Confirm the remote party's name and avatar are correct.
- [ ] Confirm two-way audio is clear and does not echo or distort.
- [ ] Mute and unmute locally; confirm both BetterTG and the remote party reflect
  the new state.
- [ ] Switch between the receiver, speaker, and an available Bluetooth route.
- [ ] Confirm signal-strength and weak-connection indicators update plausibly.
- [ ] Minimize the call, move through the app, and restore the full call view.
- [ ] End the call from BetterTG and confirm it ends promptly on both devices.

### Incoming call and CallKit

- [ ] Receive an audio call while BetterTG is in the foreground.
- [ ] Receive an audio call while BetterTG is backgrounded and while the phone
  is locked.
- [ ] Answer and decline from the native CallKit screen.
- [ ] Mute from CallKit and confirm the BetterTG call UI stays synchronized.
- [ ] End the call from CallKit and confirm BetterTG clears the active-call UI.
- [ ] Confirm the contact name is correct in the Phone app's Recents list.
- [ ] Redial from Recents and confirm BetterTG starts the intended call.
- [ ] Confirm a second incoming call receives the expected busy behavior while
  another call is active.

### Audio interruption and lifecycle

- [ ] Lock and unlock the phone during an active call.
- [ ] Background and foreground BetterTG repeatedly.
- [ ] Trigger an audio interruption, such as Siri or another system audio app,
  and confirm the call recovers.
- [ ] Connect and disconnect wired or Bluetooth audio during the call.
- [ ] Confirm the screen stays awake while the full call UI is visible.
- [ ] Confirm call tones are appropriate for ringing, busy, failure, reconnect,
  and ending states.

## Private video calls

- [ ] Start an outgoing video call and confirm the local camera preview appears
  before video is published.
- [ ] Answer an incoming video call with the camera enabled.
- [ ] Confirm local and remote video appear with the correct aspect, rotation,
  and mirroring.
- [ ] Turn the camera off and on from both devices.
- [ ] Switch between the front and rear cameras.
- [ ] Swap the primary and secondary video surfaces.
- [ ] Rotate each device while sending video and confirm the remote image remains
  correctly oriented.
- [ ] Deny camera permission and confirm the explanation and Settings action are
  useful; grant permission and retry.
- [ ] Move BetterTG to the background and confirm video and audio behavior match
  iOS expectations.

## Picture in Picture

- [ ] Enter Picture in Picture during a private video call.
- [ ] Confirm remote video remains live and correctly cropped in the PiP window.
- [ ] Move and resize the PiP window.
- [ ] Background BetterTG while PiP is active.
- [ ] Return to BetterTG from the app icon and confirm the full call view is
  restored rather than remaining hidden behind PiP.
- [ ] Return to BetterTG by tapping the PiP window and confirm the call view is
  restored correctly.
- [ ] Confirm audio, camera, and mute state remain synchronized throughout.
- [ ] End the call while PiP is active and confirm the PiP window disappears.

## Conference creation and joining

- [ ] Create a voice chat or conference from a supported group.
- [ ] Join an existing conference from the group UI.
- [ ] Join from a valid conference invite link.
- [ ] Try an expired or invalid invite link and confirm a useful failure state.
- [ ] Upgrade an active private call to a conference and confirm the original
  participant remains connected.
- [ ] Leave the conference without ending it for everyone.
- [ ] As an authorized participant, choose End for Everyone, cancel once, then
  confirm it and verify the conference ends for all participants.
- [ ] Confirm reconnecting after a brief interruption does not create duplicate
  local participants or stale UI.

## Conference participants and moderation

- [ ] Test with at least three participants, including the current user.
- [ ] Confirm participant names, avatars, speaking indicators, mute state, and
  hand-raised state update on all devices.
- [ ] Raise and lower the current user's hand.
- [ ] Cancel a pending request to speak.
- [ ] Invite a contact with audio and with video.
- [ ] Cancel a pending invitation and confirm the UI updates.
- [ ] Scroll or paginate through a conference with more participants than fit on
  screen.
- [ ] Open a participant's conversation from the participant menu.
- [ ] Open the current user's profile-editing action where available.
- [ ] Change an individual participant's playback volume and confirm the audible
  result.
- [ ] Mute or unmute another participant when permissions allow it.
- [ ] Remove a participant, cancel the confirmation once, then complete it.
- [ ] Confirm unavailable moderation actions are not offered to users without
  permission.

## Conference messages and encryption

- [ ] Open and close the conference message panel.
- [ ] Send messages from multiple participants and confirm ordering and sender
  identity.
- [ ] Confirm new messages appear in the compact in-call feed and the feed keeps
  the newest message visible.
- [ ] Send an empty message, an overly long message, and a message containing
  links or Telegram entities; confirm validation and rendering are sensible.
- [ ] Confirm incoming participant and call-state announcements do not obscure
  controls or remain on screen indefinitely.
- [ ] Expand and collapse the conference encryption key.
- [ ] Compare the encryption emojis between participating clients where the
  other client exposes the same verification key.

## Conference video layout and controls

- [ ] Publish the local camera and confirm every participant can receive it.
- [ ] Receive simultaneous video from at least two remote participants.
- [ ] Confirm the active or dominant speaker is prioritized without erratic
  switching.
- [ ] Select a video tile to expand it and return to the grid with the button and
  the downward swipe gesture.
- [ ] Pin and unpin a central video; confirm automatic speaker switching respects
  the pinned state.
- [ ] Tap the expanded video to hide and restore conference controls.
- [ ] Use the actions attached to a participant's video tile.
- [ ] Change incoming video quality and confirm video continues without freezing.
- [ ] Turn cameras on and off repeatedly and confirm tiles appear and disappear
  without stale frames.
- [ ] Confirm local and remote video rotation and mirroring remain correct.

## Screen sharing

- [ ] Start screen sharing from the system broadcast picker.
- [ ] Confirm remote participants receive the shared screen with the correct
  orientation and usable frame rate.
- [ ] Play device audio during the broadcast and confirm it is received when the
  source supports broadcast audio.
- [ ] Rotate the sharing device and switch between portrait and landscape apps.
- [ ] Enter PiP or background BetterTG while sharing and confirm the broadcast
  remains in the expected state.
- [ ] Stop sharing from BetterTG and confirm the UI changes immediately, the
  broadcast ends, and no additional frames or audio are published.
- [ ] Stop sharing from the system broadcast UI and confirm BetterTG updates.
- [ ] Start a second sharing session after stopping the first.
- [ ] Deny or interrupt screen recording and confirm the failure state is clear
  and the call remains usable.

## Orientation and responsive layout

- [ ] Verify private-call UI in portrait on each supported iPhone size available.
- [ ] Confirm a conference permits landscape rotation while an ordinary private
  call remains portrait-only where intended.
- [ ] In iPhone landscape, confirm conference controls use the right sidebar and
  do not cover video or participant content.
- [ ] Rotate repeatedly between portrait and both landscape directions during a
  conference.
- [ ] Expand video, open messages, show the participant picker, and rotate in
  each state.
- [ ] Leave the conference and confirm the rest of the app returns to its normal
  orientation behavior.
- [ ] On iPad, verify split view, full screen, portrait, and landscape without
  clipped controls or unusable sheets.

## Network and recovery

- [ ] Start a call on Wi-Fi, move to cellular, and return to Wi-Fi.
- [ ] Test at least one LTE and one 5G connection when available.
- [ ] Enable reduced-data mode and confirm audio remains usable and video quality
  adapts appropriately.
- [ ] Temporarily disable connectivity and confirm reconnecting state, tones, and
  recovery after connectivity returns.
- [ ] Test a slow or lossy network and confirm controls remain responsive.
- [ ] If SOCKS5 proxy support is configured, place a call through the proxy and
  confirm connection and media flow.
- [ ] Terminate the call from the remote device during reconnect and confirm
  BetterTG leaves no active call or PiP UI behind.

## Accessibility

- [ ] With VoiceOver enabled, start, answer, operate, minimize, restore, and end a
  private call without relying on visual position.
- [ ] Confirm visible button titles are not announced twice and icon-only controls
  have accurate names and states.
- [ ] Confirm mute, camera, speaker route, participant, message, PiP, and screen
  sharing state changes are announced once and at useful times.
- [ ] Navigate the conference participant list and video tiles with VoiceOver;
  confirm participant actions remain reachable.
- [ ] Verify Dynamic Type through the largest accessibility sizes in portrait and
  landscape without losing essential controls.
- [ ] Enable Reduce Motion and confirm message, encryption-key, and conference
  transitions avoid large movement while remaining understandable.
- [ ] Enable Increase Contrast, Reduce Transparency, and Differentiate Without
  Color individually and confirm status and controls remain recognizable.
- [ ] Test Voice Control or Switch Control for the primary call actions if those
  input methods are part of the release accessibility target.

## Failure handling and cleanup

- [ ] Decline, cancel, miss, and fail calls from both sides; confirm each outcome
  clears the active UI and allows a new call immediately.
- [ ] Force-close BetterTG during ringing, connecting, and an active call, then
  relaunch and confirm there is no unrecoverable stale state.
- [ ] Receive a call invitation for a deleted or unavailable account and confirm
  the error does not block the app.
- [ ] Trigger camera, conference invitation, local video, and screen-sharing
  failures where practical and confirm the call itself remains usable.
- [ ] End calls from BetterTG, CallKit, the remote client, PiP, and the conference
  owner flow; confirm each path cleans up audio, video, screen sharing, and the
  idle timer.
- [ ] After a completed call, submit a rating with and without detailed problems
  and comments; also test Not Now and a failed submission.
- [ ] Place a new private call and join a new conference immediately after the
  previous session ends.

## Suggested smoke-test subset

Use this shorter pass after small call-related changes:

- [ ] Complete one outgoing and one incoming private audio call.
- [ ] Toggle mute, change audio route, minimize, restore, and end from CallKit.
- [ ] Complete one private video call with camera switching and PiP restoration.
- [ ] Join a three-person conference and verify audio, messages, participant
  updates, and one remote video.
- [ ] Rotate the conference to landscape and exercise the side controls.
- [ ] Start and stop screen sharing once, confirming the remote side stops
  immediately.
- [ ] Interrupt connectivity briefly and confirm the call recovers.
- [ ] Repeat the primary controls once with VoiceOver and Reduce Motion enabled.

## Test result template

Copy this block for each test session:

```text
Build/commit:
Date:
Tester(s):
BetterTG device and iOS:
Remote device/client:
Networks used:

Private audio: PASS / FAIL / NOT TESTED
Private video: PASS / FAIL / NOT TESTED
CallKit and lifecycle: PASS / FAIL / NOT TESTED
PiP: PASS / FAIL / NOT TESTED
Conference audio and participants: PASS / FAIL / NOT TESTED
Conference video: PASS / FAIL / NOT TESTED
Conference messages: PASS / FAIL / NOT TESTED
Screen sharing: PASS / FAIL / NOT TESTED
Orientation and iPad: PASS / FAIL / NOT TESTED
Network recovery: PASS / FAIL / NOT TESTED
Accessibility: PASS / FAIL / NOT TESTED
Cleanup and rating: PASS / FAIL / NOT TESTED

Issues found:
-
```
