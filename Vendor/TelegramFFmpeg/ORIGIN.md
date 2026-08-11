# Origin

The binary in this package is built from Telegram-iOS commit
`6ad963e5b62d354da79040f388ae2b9132fb17b8`:

- FFmpeg 7.1.1 from `submodules/ffmpeg`
- libvpx from `third-party/libvpx` at commit
  `e7bfd8b6c230a6824e7fd1efa2378a7322986128`

`Scripts/build-xcframework.sh` reproduces the binary. It uses a sibling
Telegram-iOS checkout when that checkout is already at the pinned revision;
otherwise it downloads the pinned sources into the ignored `.build-sources`
directory. Set `TELEGRAM_IOS_SOURCE` to use an explicit checkout.

From the BetterTG repository root, run:

```shell
./Scripts/build-dependencies.sh
```

Pass `--force` to recreate the XCFramework from cached slices or `--clean`
to rebuild every slice. BetterTG enables only the Matroska demuxer, WebM
muxer, libvpx VP9 decoder and encoder, file protocol, and VP9 superframe
bitstream filter required to read and export Telegram video stickers.
