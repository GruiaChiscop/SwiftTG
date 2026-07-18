# Platform Code-Sharing Audit

## Sharing rule

BetterTG should share Telegram domain rules, TDLib commands, state reducers, and
platform-independent formatting. SwiftUI/AppKit composition, focus behavior,
notifications, menu-bar integration, and OS media controls should remain in the
platform targets.

This keeps bug fixes consistent without creating a single oversized view model or
forcing iOS and macOS to have identical interaction models.

## Shared today

- `TelegramSession` and the `TelegramService` abstraction.
- Chat-list, message, file, and update stores.
- Message metadata, editing, sender resolution, reactions, service-message text,
  login guidance, audio streaming, voice recording, and outgoing text-entity
  detection and merging.
- Chat-list TDLib commands in `TelegramChatActions`.
- Chat-list action availability and labels in `TelegramChatActionPolicy`.
- Mute choices and durations in `TelegramMutePreset`.
- Reaction, pin/unpin, and message-deletion commands in
  `TelegramMessageActions`.
- Country mapping, calling-code resolution, phone-number display, and E.164
  normalization in `TelegramPhoneNumber`.
- Service-sound resource names and throttling in `TelegramServiceSoundPolicy`.
- Text, photo, document, reply, single-message, and album sending semantics in
  `TelegramMessageSending`.
- Voice-note staging paths, waveform packing, TDLib content construction, upload
  actions, sending, and post-upload cleanup in `TelegramVoiceNoteSending` and
  `TelegramVoiceNoteStaging`.
- Apple push-token registration, TDLib authorization coordination, session
  replacement, and encrypted-payload processing in
  `TelegramApplePushRegistration`.

## Consolidated in this pass

### Chat-list action policy

Previously, iOS and macOS independently decided whether to show Clear History,
Leave Group/Channel, or Delete Chat/Group/Channel. They now consume the same
policy based on chat kind, membership, and TDLib deletion flags.

### Mute presets

The same four titles and durations were repeated in the iOS chat list, macOS chat
list, and macOS Chat Info. They now come from one shared enum.

### Message commands

Reaction toggling, pin/unpin, and message deletion previously called TDLib
independently from `ChatVM` and `MacSessionModel`. Their command semantics now
live in one shared implementation; the platform models only schedule work and
present errors.

## Remaining candidates

### Phone login and country selection

Both platforms load countries, map `CountryInfo` to `PhoneNumberInfo`, select the
current country, normalize phone numbers, and submit authentication data. The
shared mapping and normalization are now extracted. macOS manual calling-code
entry consumes the same resolver, and both platforms submit the same E.164 form.
The authorization-screen state machines remain separate because macOS additionally
supports session replacement.

### 2. Voice-message Opus playback — high value, high risk

`BetterTG/Models/Media.swift` and `BetterTGMac/MacVoicePlayer.swift` both decode
Opus, create PCM buffers, schedule `AVAudioPlayerNode`, seek, and update progress.
The decoder and playback engine can be shared. Keep `AVAudioSession`, lock-screen
commands, and `MPNowPlayingInfoCenter` in an iOS adapter.

This should be done only with playback, switching, seeking, legacy-message, and
VoiceOver-focus tests because regressions have occurred in this area before.

### Composer and media sending

Text, photo, document, reply, edit, and typing-action flows exist in both
`ChatVM` and `MacSessionModel`. Text, photo, document, reply, single-message versus
album selection, voice-note staging and waveform packing, upload actions, and
cancellation are now shared. Draft state, pickers, image inspection, focus,
microphone permission, recording UI, and presentation remain platform-specific.
The recorder follows Telegram iOS by encoding Ogg/Opus incrementally into memory.
Because TDLib requires an input-file path, BetterTG writes the completed recording
to a dedicated temporary staging directory. The staging file is retained while
TDLib uploads it, removed on `updateMessageSendSucceeded`, retained on a send
failure so Retry can still work, and removed as abandoned after 24 hours.

### Service-sound throttling

The debounce timestamps and resource names are now shared. `AudioServices` on iOS
and `NSSound` on macOS correctly remain separate backends.

### 5. Conversation orchestration — medium/high risk

Both platform models load history, resolve reply/forward/sender data, and react to
message updates. Most storage is already shared through `TelegramMessageStore`.
Further consolidation should use small coordinators rather than merging
`ChatVM` and `MacSessionModel` into one `@MainActor` object.

## Intentionally platform-specific

- UIKit/AppKit accessibility containers and focus movement.
- iOS navigation-controller integration and macOS split-view/table navigation.
- UIKit/AppKit APNs authorization and application-delegate callbacks.
- Menu-bar lifecycle and TDLib-backed local notification presentation on macOS.
- Photo/document pickers and previews.
- iOS audio-session and lock-screen controls.
- macOS application termination and menu-bar lifecycle.

## Recommended order

1. Extract more conversation resolution coordinators in small pieces.
2. Refactor Opus playback last, with dedicated manual and automated coverage.
