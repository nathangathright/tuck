#!/usr/bin/env bash
set -euo pipefail

NOTARY_PROFILE="${NOTARY_PROFILE:-tuck-notary}"

if ! command -v xcode-select >/dev/null 2>&1; then
  echo "Xcode command line tools are not available."
  exit 1
fi

echo "Xcode: $(xcode-select -p)"

if ! xcrun --find notarytool >/dev/null 2>&1; then
  echo "notarytool is not available through xcrun."
  exit 1
fi

if ! xcrun --find stapler >/dev/null 2>&1; then
  echo "stapler is not available through xcrun."
  exit 1
fi

echo "notarytool: $(xcrun --find notarytool)"
echo "stapler: $(xcrun --find stapler)"

developer_id_identities="$(security find-identity -v -p codesigning | grep "Developer ID Application" || true)"

if [[ -z "$developer_id_identities" ]]; then
  cat <<EOF
No usable Developer ID Application identity was found in this keychain.

Create one in Xcode:
  Xcode > Settings > Accounts > Manage Certificates... > + > Developer ID Application

Or create one in the Apple Developer account portal, then double-click the
downloaded .cer file on the same Mac that generated the CSR.
EOF
  exit 2
fi

echo "Developer ID Application identities:"
echo "$developer_id_identities"

if [[ "${CHECK_NOTARY_PROFILE:-0}" == "1" ]]; then
  echo "Checking notary profile: $NOTARY_PROFILE"
  xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null
  echo "Notary profile is valid."
else
  cat <<EOF
Notary profile check skipped.
Run this after storing credentials:
  CHECK_NOTARY_PROFILE=1 NOTARY_PROFILE=$NOTARY_PROFILE Scripts/check-notarization-setup.sh
EOF
fi
