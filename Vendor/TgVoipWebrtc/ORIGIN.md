# Origin

The binary in this package is built from Telegram-iOS commit
`6ad963e5b62d354da79040f388ae2b9132fb17b8` (fork at
`github.com/GruiaChiscop/Telegram-iOS`), target
`//submodules/TgVoipWebrtc:TgVoipWebrtcFramework`.

That target does not exist upstream — it was added to
`submodules/TgVoipWebrtc/BUILD` in the fork (an `ios_static_framework` wrapping
the existing `TgVoipWebrtc` `objc_library`, with `bundle_name = "TgVoipWebrtc"`
so the framework-relative `#import <TgVoipWebrtc/...>` in the headers still
resolves, `hdrs` added so the two public headers get bundled and an umbrella
header generated, and `"Network"` added to the underlying `objc_library`'s
`sdk_frameworks` because `RTCNetworkMonitor` needs it and nothing else in the
dependency graph declared it).

The `.framework` that Bazel produces is bundled as a *static* framework
(no `Info.plist`, an `ar` archive instead of a Mach-O dylib inside). Xcode's
SwiftPM integration tries to embed any `.framework`-shaped binary target into
the app bundle and fails validation (`did not contain an Info.plist`) when it
does. To sidestep that, this package repackages the build output as a
**library**-style xcframework instead (`libTgVoipWebrtc.a` + a `Headers`
directory, matching the `Vendor/TelegramFFmpeg` pattern) rather than passing
the `.framework` straight to `-create-xcframework`. The headers are nested
under a `TgVoipWebrtc/` subdirectory (mirroring the original
`PublicHeaders/TgVoipWebrtc/` layout) so their internal
`#import <TgVoipWebrtc/...>` imports keep resolving; `Sources/TgVoipWebrtc`
carries its own copy of those same headers under `include/TgVoipWebrtc/` so
SwiftPM synthesizes a `TgVoipWebrtc` module for `import TgVoipWebrtc` to work.
That synthesized module map also doesn't carry the original xcframework's
`link framework "..."` directives (AVFoundation, VideoToolbox, etc.) or
`link "bz2"/"iconv"/"z"/"c++"`, so `Package.swift`'s `linkerSettings`
re-declares all of them explicitly - without them the app compiles but fails
at final link with missing symbols (first hit: `kVTProfileLevel_H264_Main_AutoLevel`
from the statically-linked H264 encoder, even though this app never touches
video - static libraries pull in whole object files, not just used symbols).

A second, separate static-linking gotcha only shows up at *runtime*, not link
time: tgcalls adds `maxSupportedH264Profile` as an Objective-C **category** on
`UIDevice`. Categories in a statically-linked `.a` don't get loaded at all
unless the `-ObjC` linker flag is passed - unlike missing symbols, this fails
silently at build and link time and only crashes the first time something
calls the category method (`"unrecognized selector sent to class"`). Passed
via `.unsafeFlags(["-Xlinker", "-ObjC"])` in `Package.swift`; the app project's
own `OTHER_LDFLAGS` doesn't set it project-wide.

The Swift package product itself is deliberately **dynamic**, even though its
binary target contains a static archive. TDLib also embeds OpenSSL, while this
archive embeds WebRTC's BoringSSL; both export identically named `BN_*` symbols.
Putting both archives in the app's Mach-O allowed the linker to mix objects from
the two implementations. TDLib then failed its first call DH validation with
`Bad prime mod 4g`. Linking the wrapper as its own dynamic framework isolates
the crypto implementations through Mach-O's two-level namespace.

This is a **debug** build (`-c dbg`), unstripped and unoptimized — fine for
initial integration, but it should be rebuilt with `-c opt` before shipping
(expect a large size reduction from the current ~1.5GB).

iOS only: `ios-arm64` (device) + `ios-arm64-simulator`. No macOS slice yet —
`TgVoipWebrtc`'s own BUILD file already has macOS arm64 support patched in
(see `submodules/TgVoipWebrtc/CLAUDE.md` in that fork), so a macOS build is a
separate future addition, not a rebuild of this target.

## Reproducing

From a checkout of the fork at the pinned commit:

```shell
BAZEL=./build-input/bazel-8.4.2-darwin-arm64   # or your own Bazel 8.4.2
CACHE=~/telegram-bazel-cache                    # optional disk cache, speeds up a lot

for cpu in sim_arm64 arm64; do
  "$BAZEL" build //submodules/TgVoipWebrtc:TgVoipWebrtcFramework \
    -c dbg --ios_multi_cpus=$cpu --disk_cache="$CACHE"
  mkdir -p /tmp/tgvoip-lib/$cpu
  unzip -o -q bazel-bin/submodules/TgVoipWebrtc/TgVoipWebrtcFramework.zip \
    -d /tmp/tgvoip-lib/$cpu
  cp /tmp/tgvoip-lib/$cpu/TgVoipWebrtc.framework/TgVoipWebrtc \
    /tmp/tgvoip-lib/$cpu/libTgVoipWebrtc.a
  mkdir -p /tmp/tgvoip-lib/$cpu/Headers/TgVoipWebrtc
  mv /tmp/tgvoip-lib/$cpu/TgVoipWebrtc.framework/Headers/*.h \
    /tmp/tgvoip-lib/$cpu/Headers/TgVoipWebrtc/
done

xcodebuild -create-xcframework \
  -library /tmp/tgvoip-lib/arm64/libTgVoipWebrtc.a -headers /tmp/tgvoip-lib/arm64/Headers \
  -library /tmp/tgvoip-lib/sim_arm64/libTgVoipWebrtc.a -headers /tmp/tgvoip-lib/sim_arm64/Headers \
  -output TgVoipWebrtc.xcframework

# Sources/TgVoipWebrtc/include/TgVoipWebrtc/ also needs a copy of the three
# headers (MediaStreaming.h, OngoingCallThreadLocalContext.h, TgVoipWebrtc.h)
# from either slice's Headers/TgVoipWebrtc/ — they're identical across slices.
```
