#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PACKAGE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPOSITORY_DIR="$(cd "$PACKAGE_DIR/../.." && pwd)"
JOBS="${TELEGRAM_FFMPEG_JOBS:-4}"
WORK_DIR="${TELEGRAM_FFMPEG_WORK_DIR:-$PACKAGE_DIR/.build-artifacts}"
OUTPUT="$PACKAGE_DIR/TelegramFFmpegBinary.xcframework"

TELEGRAM_COMMIT="6ad963e5b62d354da79040f388ae2b9132fb17b8"
TELEGRAM_REPOSITORY="${TELEGRAM_IOS_REPOSITORY:-https://github.com/TelegramMessenger/Telegram-iOS.git}"
LIBVPX_COMMIT="e7bfd8b6c230a6824e7fd1efa2378a7322986128"
FFMPEG_VERSION="7.1.1"
MANAGED_TELEGRAM_SOURCE="$PACKAGE_DIR/.build-sources/Telegram-iOS"
SIBLING_TELEGRAM_SOURCE="$(cd "$REPOSITORY_DIR/.." && pwd)/Telegram-iOS"

FORCE=false
CLEAN=false

usage() {
    echo "Usage: $0 [--force] [--clean]"
    echo
    echo "  --force  Recreate the XCFramework while reusing compiled slices."
    echo "  --clean  Remove compiled slices and rebuild everything."
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --force)
            FORCE=true
            ;;
        --clean)
            CLEAN=true
            FORCE=true
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
    shift
done

for command in git make patch pkg-config xcodebuild xcrun; do
    if ! command -v "$command" >/dev/null 2>&1; then
        echo "Missing required command: $command" >&2
        exit 1
    fi
done

if [[ -d "$OUTPUT" && "$FORCE" == false ]]; then
    echo "Already built: $OUTPUT"
    exit 0
fi

if [[ "$CLEAN" == true ]]; then
    rm -rf "$WORK_DIR"
fi

TELEGRAM_SOURCE_IS_MANAGED=false
if [[ -n "${TELEGRAM_IOS_SOURCE:-}" ]]; then
    TELEGRAM_SOURCE="$TELEGRAM_IOS_SOURCE"
elif [[ -d "$SIBLING_TELEGRAM_SOURCE/.git" ]] \
    && [[ "$(git -C "$SIBLING_TELEGRAM_SOURCE" rev-parse HEAD)" == "$TELEGRAM_COMMIT" ]]; then
    TELEGRAM_SOURCE="$SIBLING_TELEGRAM_SOURCE"
else
    TELEGRAM_SOURCE="$MANAGED_TELEGRAM_SOURCE"
    TELEGRAM_SOURCE_IS_MANAGED=true
fi

prepare_managed_telegram_source() {
    if [[ ! -d "$TELEGRAM_SOURCE/.git" ]]; then
        mkdir -p "$TELEGRAM_SOURCE"
        git -C "$TELEGRAM_SOURCE" init
        git -C "$TELEGRAM_SOURCE" remote add origin "$TELEGRAM_REPOSITORY"
    fi

    git -C "$TELEGRAM_SOURCE" fetch --depth 1 origin "$TELEGRAM_COMMIT"
    git -C "$TELEGRAM_SOURCE" checkout --detach FETCH_HEAD
    git -C "$TELEGRAM_SOURCE" submodule update --init --depth 1 third-party/libvpx/libvpx
}

if [[ "$TELEGRAM_SOURCE_IS_MANAGED" == true ]]; then
    prepare_managed_telegram_source
fi

FFMPEG_SOURCE="$TELEGRAM_SOURCE/submodules/ffmpeg/Sources/FFMpeg/ffmpeg-$FFMPEG_VERSION"
LIBVPX_SOURCE="$TELEGRAM_SOURCE/third-party/libvpx/libvpx"
LIBVPX_BUILD_SCRIPT="$TELEGRAM_SOURCE/third-party/libvpx/build-libvpx-bazel.sh"
LIBVPX_SIMULATOR_PATCH="$TELEGRAM_SOURCE/third-party/libvpx/0001-Support-arm64-simulator.patch"
LIBVPX_DEPLOYMENT_PATCH="$PACKAGE_DIR/Patches/libvpx-macos-deployment-target.patch"
LIBVPX_CODEC_PATCH="$PACKAGE_DIR/Patches/libvpx-vp9-codec.patch"

if [[ ! -f "$FFMPEG_SOURCE/configure" || ! -f "$LIBVPX_SOURCE/configure" ]]; then
    echo "Required Telegram-iOS sources not found at: $TELEGRAM_SOURCE" >&2
    exit 1
fi

ACTUAL_COMMIT="$(git -C "$TELEGRAM_SOURCE" rev-parse HEAD)"
if [[ "$ACTUAL_COMMIT" != "$TELEGRAM_COMMIT" ]]; then
    echo "Expected Telegram-iOS $TELEGRAM_COMMIT, found $ACTUAL_COMMIT" >&2
    exit 1
fi

ACTUAL_LIBVPX_COMMIT="$(git -C "$LIBVPX_SOURCE" rev-parse HEAD)"
if [[ "$ACTUAL_LIBVPX_COMMIT" != "$LIBVPX_COMMIT" ]]; then
    echo "Expected libvpx $LIBVPX_COMMIT, found $ACTUAL_LIBVPX_COMMIT" >&2
    exit 1
fi

mkdir -p "$WORK_DIR"

build_slice() {
    local name="$1"
    local vpx_arch="$2"
    local sdk="$3"
    local target="$4"
    local minimum_flag="$5"
    local slice_dir="$WORK_DIR/$name"
    local vpx_source_copy="$slice_dir/libvpx-source"
    local vpx_build="$slice_dir/libvpx-build"
    local vpx_build_script="$slice_dir/build-libvpx.sh"
    local vpx_prefix="$slice_dir/libvpx-prefix"
    local ffmpeg_build="$slice_dir/ffmpeg-build"
    local ffmpeg_install="$slice_dir/ffmpeg-install"
    local combined="$slice_dir/libTelegramFFmpegBinary.a"
    local headers="$slice_dir/Headers"

    if [[ -f "$combined" && -f "$headers/module.modulemap" ]]; then
        return
    fi

    mkdir -p "$slice_dir"
    if [[ ! -f "$vpx_build/VPX.framework/VPX" ]]; then
        mkdir -p "$vpx_source_copy" "$vpx_build"
        ditto "$LIBVPX_SOURCE" "$vpx_source_copy"
        patch -d "$vpx_source_copy" -p1 < "$LIBVPX_SIMULATOR_PATCH"
        patch -d "$vpx_source_copy" -p1 < "$LIBVPX_DEPLOYMENT_PATCH"
        cp "$LIBVPX_BUILD_SCRIPT" "$vpx_build_script"
        patch "$vpx_build_script" < "$LIBVPX_CODEC_PATCH"
        bash "$vpx_build_script" "$vpx_arch" "$vpx_source_copy" "$vpx_build"
    fi

    mkdir -p "$vpx_prefix/include" "$vpx_prefix/lib" "$vpx_prefix/pkgconfig"
    ditto "$vpx_build/VPX.framework/Headers/vpx" "$vpx_prefix/include/vpx"
    cp "$vpx_build/VPX.framework/VPX" "$vpx_prefix/lib/libVPX.a"
    {
        echo "prefix=$vpx_prefix"
        echo 'exec_prefix=${prefix}'
        echo 'libdir=${prefix}/lib'
        echo 'includedir=${prefix}/include'
        echo
        echo 'Name: vpx'
        echo 'Description: WebM VP8/VP9 codec SDK'
        echo 'Version: 1.13.1'
        echo 'Libs: -L${libdir} -lVPX -lm -lpthread'
        echo 'Cflags: -I${includedir}'
    } > "$vpx_prefix/pkgconfig/vpx.pc"

    mkdir -p "$ffmpeg_build" "$ffmpeg_install"
    pushd "$ffmpeg_build" >/dev/null
    PKG_CONFIG_PATH="$vpx_prefix/pkgconfig" \
    "$FFMPEG_SOURCE/configure" \
        --prefix="$ffmpeg_install" \
        --target-os=darwin \
        --arch=arm64 \
        --cc="xcrun -sdk $sdk clang" \
        --enable-cross-compile \
        --enable-pic \
        --enable-small \
        --disable-programs \
        --disable-doc \
        --disable-debug \
        --disable-autodetect \
        --disable-network \
        --disable-everything \
        --disable-avdevice \
        --disable-avfilter \
        --disable-swresample \
        --disable-swscale \
        --enable-avcodec \
        --enable-avformat \
        --enable-avutil \
        --enable-libvpx \
        --enable-decoder=libvpx_vp9 \
        --enable-encoder=libvpx_vp9 \
        --enable-demuxer=matroska \
        --enable-muxer=webm \
        --enable-protocol=file \
        --enable-bsf=vp9_superframe \
        --extra-cflags="-arch arm64 $minimum_flag --target=$target" \
        --extra-ldflags="-arch arm64 $minimum_flag --target=$target" \
        --pkg-config-flags=--static
    make -j"$JOBS" install
    popd >/dev/null

    xcrun -sdk "$sdk" libtool -static -o "$combined" \
        "$ffmpeg_install/lib/libavformat.a" \
        "$ffmpeg_install/lib/libavcodec.a" \
        "$ffmpeg_install/lib/libavutil.a" \
        "$vpx_prefix/lib/libVPX.a"

    mkdir -p "$headers"
    ditto "$ffmpeg_install/include/libavformat" "$headers/libavformat"
    ditto "$ffmpeg_install/include/libavcodec" "$headers/libavcodec"
    ditto "$ffmpeg_install/include/libavutil" "$headers/libavutil"
    cp "$PACKAGE_DIR/Sources/TelegramFFmpegBinary/TelegramFFmpegBinary.h" "$headers/TelegramFFmpegBinary.h"
    cp "$PACKAGE_DIR/Sources/TelegramFFmpegBinary/module.modulemap" "$headers/module.modulemap"
}

build_slice "ios-arm64" "arm64" "iphoneos" "arm64-apple-ios17.0" "-mios-version-min=17.0"
build_slice "ios-simulator-arm64" "sim_arm64" "iphonesimulator" "arm64-apple-ios17.0-simulator" "-mios-simulator-version-min=17.0"
build_slice "macos-arm64" "macos_arm64" "macosx" "arm64-apple-macos15.0" "-mmacosx-version-min=15.0"

TEMP_OUTPUT="$WORK_DIR/TelegramFFmpegBinary.xcframework"
rm -rf "$TEMP_OUTPUT"

xcodebuild -create-xcframework \
    -library "$WORK_DIR/ios-arm64/libTelegramFFmpegBinary.a" \
    -headers "$WORK_DIR/ios-arm64/Headers" \
    -library "$WORK_DIR/ios-simulator-arm64/libTelegramFFmpegBinary.a" \
    -headers "$WORK_DIR/ios-simulator-arm64/Headers" \
    -library "$WORK_DIR/macos-arm64/libTelegramFFmpegBinary.a" \
    -headers "$WORK_DIR/macos-arm64/Headers" \
    -output "$TEMP_OUTPUT"

if [[ -e "$OUTPUT" ]]; then
    rm -rf "$OUTPUT"
fi
mv "$TEMP_OUTPUT" "$OUTPUT"

echo "Created $OUTPUT"
