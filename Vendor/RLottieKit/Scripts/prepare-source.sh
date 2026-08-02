#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PACKAGE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SOURCE_DIR="$PACKAGE_DIR/Sources/RLottieCore/rlottie"
RLOTTIE_REPOSITORY="https://github.com/TelegramMessenger/rlottie.git"
RLOTTIE_COMMIT="67f103bc8b625f2a4a9e94f1d8c7bd84c5a08d1d"

if [[ -e "$SOURCE_DIR" && ! -d "$SOURCE_DIR/.git" ]]; then
    echo "error: $SOURCE_DIR exists but is not a generated rlottie checkout." >&2
    echo "Move it aside, then run this script again." >&2
    exit 1
fi

if [[ ! -d "$SOURCE_DIR/.git" ]]; then
    mkdir -p "$(dirname "$SOURCE_DIR")"
    git init --quiet "$SOURCE_DIR"
    git -C "$SOURCE_DIR" remote add origin "$RLOTTIE_REPOSITORY"
fi

ACTUAL_REPOSITORY="$(git -C "$SOURCE_DIR" remote get-url origin 2>/dev/null || true)"
if [[ "$ACTUAL_REPOSITORY" != "$RLOTTIE_REPOSITORY" ]]; then
    echo "error: expected rlottie origin $RLOTTIE_REPOSITORY, got $ACTUAL_REPOSITORY" >&2
    exit 1
fi

if [[ -n "$(git -C "$SOURCE_DIR" status --porcelain --untracked-files=all)" ]]; then
    echo "error: the generated rlottie checkout has local changes: $SOURCE_DIR" >&2
    echo "Preserve or discard those changes before updating the dependency." >&2
    exit 1
fi

if [[ "$(git -C "$SOURCE_DIR" rev-parse HEAD 2>/dev/null || true)" != "$RLOTTIE_COMMIT" ]]; then
    echo "Fetching TelegramMessenger/rlottie at $RLOTTIE_COMMIT..."
    git -C "$SOURCE_DIR" fetch --quiet --depth 1 origin "$RLOTTIE_COMMIT"
    git -C "$SOURCE_DIR" checkout --quiet --detach FETCH_HEAD
fi

ACTUAL_COMMIT="$(git -C "$SOURCE_DIR" rev-parse HEAD)"
if [[ "$ACTUAL_COMMIT" != "$RLOTTIE_COMMIT" ]]; then
    echo "error: expected rlottie $RLOTTIE_COMMIT, got $ACTUAL_COMMIT" >&2
    exit 1
fi

echo "rlottie is ready at $RLOTTIE_COMMIT."
