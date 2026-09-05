#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-$(plutil -extract CFBundleShortVersionString raw "$ROOT_DIR/Resources/Info.plist")}"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
NOTARIZE="${NOTARIZE:-0}"
NOTARY_PROFILE="${NOTARY_PROFILE:-tuck-notary}"
DIST_DIR="$ROOT_DIR/dist"
STAGING_DIR="$DIST_DIR/staging"
PACKAGE_DIR="$STAGING_DIR/Tuck-$VERSION"
ARCHIVE_PATH="$DIST_DIR/Tuck-$VERSION.zip"
NOTARY_ARCHIVE_PATH="$DIST_DIR/Tuck-$VERSION-notary.zip"
CASK_TEMPLATE="$ROOT_DIR/Packaging/Homebrew/Casks/tuck.rb.template"
CASK_OUTPUT_DIR="$DIST_DIR/homebrew"
CASK_OUTPUT="$CASK_OUTPUT_DIR/tuck.rb"

cd "$ROOT_DIR"

if [[ "$NOTARIZE" == "1" && "$CODESIGN_IDENTITY" == "-" ]]; then
  echo "NOTARIZE=1 requires CODESIGN_IDENTITY to be a Developer ID Application identity." >&2
  exit 2
fi

CODESIGN_IDENTITY="$CODESIGN_IDENTITY" UNIVERSAL=1 "$ROOT_DIR/Scripts/build-app.sh" >/dev/null
swift build -c release --product tuck --arch arm64 --arch x86_64

rm -rf "$PACKAGE_DIR" "$ARCHIVE_PATH" "$NOTARY_ARCHIVE_PATH" "$CASK_OUTPUT_DIR"
mkdir -p "$PACKAGE_DIR/bin" "$DIST_DIR" "$CASK_OUTPUT_DIR"

ditto "$ROOT_DIR/build/Tuck.app" "$PACKAGE_DIR/Tuck.app"
cp "$ROOT_DIR/.build/apple/Products/Release/tuck" "$PACKAGE_DIR/bin/tuck"
chmod +x "$PACKAGE_DIR/bin/tuck"

codesign_flags=(--force --sign "$CODESIGN_IDENTITY")

if [[ "$CODESIGN_IDENTITY" != "-" ]]; then
  codesign_flags+=(--timestamp --options runtime)
fi

codesign "${codesign_flags[@]}" --identifier "com.nathangathright.Tuck.cli" "$PACKAGE_DIR/bin/tuck" >/dev/null
codesign --verify --strict --verbose=2 "$PACKAGE_DIR/bin/tuck" >/dev/null
codesign --verify --deep --strict --verbose=2 "$PACKAGE_DIR/Tuck.app" >/dev/null

if [[ "$NOTARIZE" == "1" ]]; then
  ditto -c -k --norsrc "$PACKAGE_DIR" "$NOTARY_ARCHIVE_PATH"
  xcrun notarytool submit "$NOTARY_ARCHIVE_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait
  xcrun stapler staple "$PACKAGE_DIR/Tuck.app"
  xcrun stapler validate "$PACKAGE_DIR/Tuck.app"
  rm -f "$NOTARY_ARCHIVE_PATH"
fi

ditto -c -k --norsrc "$PACKAGE_DIR" "$ARCHIVE_PATH"

SHA256="$(shasum -a 256 "$ARCHIVE_PATH" | awk '{print $1}')"
sed \
  -e "s/__VERSION__/$VERSION/g" \
  -e "s/__SHA256__/$SHA256/g" \
  "$CASK_TEMPLATE" > "$CASK_OUTPUT"

cat <<EOF
Release archive: $ARCHIVE_PATH
SHA-256: $SHA256
Generated cask: $CASK_OUTPUT
EOF
