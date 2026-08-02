# Origin

The Swift and Objective-C++ wrapper comes from
`Telegram-iOS/Telegram/WatchApp/Packages/RLottieKit` at Telegram-iOS commit
`6ad963e5b62d354da79040f388ae2b9132fb17b8`.

The rendering engine is fetched directly from
`https://github.com/TelegramMessenger/rlottie.git` at commit
`67f103bc8b625f2a4a9e94f1d8c7bd84c5a08d1d`, the revision currently pinned by
that Telegram-iOS checkout. Run `Scripts/build-dependencies.sh` from the
repository root to prepare it. The generated checkout is not stored in Git.

BetterTG adds iOS to the wrapper's package platforms, bounds decompressed TGS
payloads to 8 MiB, and enables rlottie's thread-safe synchronous rasterizer.
