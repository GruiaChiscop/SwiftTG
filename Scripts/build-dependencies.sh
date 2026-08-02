#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPOSITORY_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

"$REPOSITORY_DIR/Vendor/RLottieKit/Scripts/prepare-source.sh"
"$REPOSITORY_DIR/Vendor/TelegramFFmpeg/Scripts/build-xcframework.sh" "$@"

echo "Local dependencies are ready."
