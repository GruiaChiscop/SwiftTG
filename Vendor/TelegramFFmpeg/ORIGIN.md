# Origin

The binary in this package is built from Telegram-iOS commit
`6ad963e5b62d354da79040f388ae2b9132fb17b8`:

- FFmpeg 7.1.1 from `submodules/ffmpeg`
- libvpx from `third-party/libvpx` at commit
  `e7bfd8b6c230a6824e7fd1efa2378a7322986128`

`Scripts/build-xcframework.sh` reproduces the binary from a sibling
Telegram-iOS checkout. BetterTG enables only the Matroska demuxer, the
libvpx VP9 decoder, the file protocol, and the VP9 superframe bitstream
filter required for Telegram video stickers.
