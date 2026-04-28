#!/usr/bin/env bash
# Build Magpie via SPM and assemble Magpie.app for personal use.
set -euo pipefail

cd "$(dirname "$0")"

CONFIG="${1:-release}"
APP_NAME="Magpie"
APP_DIR="$APP_NAME.app"
INFO_PLIST="Sources/Magpie/Resources/Info.plist"
# Build outside Documents/ — llbuild's sqlite hits I/O errors on some Documents setups.
BUILD_PATH="/tmp/magpie-build"

echo "==> swift build -c $CONFIG (build path: $BUILD_PATH)"
swift build -c "$CONFIG" --build-path "$BUILD_PATH"

BIN_PATH="$(swift build -c "$CONFIG" --build-path "$BUILD_PATH" --show-bin-path)/$APP_NAME"
if [[ ! -x "$BIN_PATH" ]]; then
    echo "Build did not produce $BIN_PATH" >&2
    exit 1
fi

echo "==> Assembling $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "$INFO_PLIST" "$APP_DIR/Contents/Info.plist"

# Ad-hoc sign so macOS is willing to grant the app stable Accessibility permission.
echo "==> codesign --force --sign -"
codesign --force --deep --sign - "$APP_DIR" >/dev/null

echo "==> Done: $(pwd)/$APP_DIR"
echo "Run with:  open $APP_DIR"
