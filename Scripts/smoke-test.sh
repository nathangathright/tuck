#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

swift test
"$ROOT_DIR/Scripts/build-app.sh"
swift build -c release --product tuck
"$ROOT_DIR/.build/release/tuck" --version

if command -v ffmpeg >/dev/null 2>&1 && command -v ffprobe >/dev/null 2>&1; then
  TMP_DIR="$(mktemp -d /tmp/tuck-smoke.XXXXXX)"
  trap 'rm -R "$TMP_DIR"' EXIT

  SOURCE="$TMP_DIR/sample.mov"
  OUTPUT="$TMP_DIR/sample - compressed.mp4"

  ffmpeg \
    -hide_banner \
    -nostdin \
    -y \
    -f lavfi \
    -i testsrc2=size=320x180:rate=12:duration=1.5 \
    -f lavfi \
    -i sine=frequency=440:sample_rate=44100:duration=1.5 \
    -c:v libx264 \
    -pix_fmt yuv420p \
    -c:a aac \
    -shortest \
    "$SOURCE" >/dev/null 2>&1

  BEFORE_SHA="$(shasum -a 256 "$SOURCE" | awk '{print $1}')"
  "$ROOT_DIR/.build/release/tuck" "$SOURCE" >/dev/null
  AFTER_SHA="$(shasum -a 256 "$SOURCE" | awk '{print $1}')"

  test "$BEFORE_SHA" = "$AFTER_SHA"
  test -f "$OUTPUT"
  ffprobe -v error "$OUTPUT" >/dev/null
else
  echo "Skipping CLI compression smoke test because FFmpeg or FFprobe is unavailable."
fi

echo "Smoke test passed."
