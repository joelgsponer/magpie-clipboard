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

# Sign with a stable local self-signed identity so Accessibility grants survive
# rebuilds. Ad-hoc signing (`--sign -`) has no certificate identity, so macOS
# ties the TCC grant to a hash of the binary itself — every rebuild changes
# that hash and invalidates the existing Accessibility approval.
SIGN_IDENTITY="Magpie Local Codesign"
echo "==> codesign --force --sign \"$SIGN_IDENTITY\""
codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_DIR" >/dev/null

echo "==> Done: $(pwd)/$APP_DIR"
echo "Run with:  open $APP_DIR"
