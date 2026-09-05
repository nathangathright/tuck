#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-release}"
UNIVERSAL="${UNIVERSAL:-0}"
APP_DIR="$ROOT_DIR/build/Tuck.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
BINARY_PATH="$ROOT_DIR/.build/$CONFIGURATION/TuckApp"

cd "$ROOT_DIR"

if [[ "$UNIVERSAL" == "1" ]]; then
  swift build -c "$CONFIGURATION" --product TuckApp --arch arm64 --arch x86_64

  case "$CONFIGURATION" in
    debug) build_configuration_dir="Debug" ;;
    release) build_configuration_dir="Release" ;;
    *) build_configuration_dir="$CONFIGURATION" ;;
  esac

  BINARY_PATH="$ROOT_DIR/.build/apple/Products/$build_configuration_dir/TuckApp"
else
  swift build -c "$CONFIGURATION" --product TuckApp
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BINARY_PATH" "$MACOS_DIR/Tuck"
cp "$ROOT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"

if [[ -d "$ROOT_DIR/Vendor/ffmpeg" ]]; then
  mkdir -p "$RESOURCES_DIR/bin"
  cp "$ROOT_DIR/Vendor/ffmpeg/ffmpeg" "$RESOURCES_DIR/bin/ffmpeg"
  cp "$ROOT_DIR/Vendor/ffmpeg/ffprobe" "$RESOURCES_DIR/bin/ffprobe"
  chmod +x "$RESOURCES_DIR/bin/ffmpeg" "$RESOURCES_DIR/bin/ffprobe"
fi

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$APP_DIR" >/dev/null
fi

echo "$APP_DIR"
