#!/bin/bash
# Build, Developer ID sign, notarize, staple, and verify an official release candidate.
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." &>/dev/null && pwd)"
SIGNING_IDENTITY="${SIGNING_IDENTITY:?Set SIGNING_IDENTITY to the BinaryBears Developer ID Application identity}"
SIGNING_KEYCHAIN="${SIGNING_KEYCHAIN:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:?Set NOTARY_PROFILE to a notarytool Keychain profile}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$REPO_ROOT/gui/Info.plist")"
DMG="$REPO_ROOT/dist/ntfsmac-${VERSION}-Apple-Silicon.dmg"
APP="$REPO_ROOT/dist/ntfsmac.app"

[[ "$SIGNING_IDENTITY" == "Developer ID Application: BinaryBears LLC (SQY8T23X8N)" ]] || {
  echo "notarize-release: HARD-STOP — unexpected signing identity: $SIGNING_IDENTITY" >&2
  exit 1
}
[[ "$VERSION" =~ ^3\.[0-9]+\.[0-9]+$ ]] || {
  echo "notarize-release: HARD-STOP — v3 release version must use 3.x.y SemVer" >&2
  exit 1
}
[[ -z "${RELEASE_VERSION:-}" || "$RELEASE_VERSION" == "$VERSION" ]] || {
  echo "notarize-release: HARD-STOP — requested version $RELEASE_VERSION does not match $VERSION" >&2
  exit 1
}

notary_args=(--keychain-profile "$NOTARY_PROFILE")
[[ -z "$SIGNING_KEYCHAIN" ]] || notary_args+=(--keychain "$SIGNING_KEYCHAIN")

"$SCRIPT_DIR/sync-brand-assets.sh"
# build-all performs its ordinary local integrity sign; replace it exactly once with the
# official identity after every runtime binary exists.
SIGNING_IDENTITY=- SIGNING_KEYCHAIN="" "$SCRIPT_DIR/build-all.sh"
SIGNING_IDENTITY="$SIGNING_IDENTITY" SIGNING_KEYCHAIN="$SIGNING_KEYCHAIN" "$SCRIPT_DIR/sign.sh"
SIGNING_IDENTITY="$SIGNING_IDENTITY" SIGNING_KEYCHAIN="$SIGNING_KEYCHAIN" "$SCRIPT_DIR/package-app.sh"

app_zip="$(mktemp -t ntfsmac-app).zip"
trap 'rm -f "$app_zip"' EXIT
ditto -c -k --keepParent "$APP" "$app_zip"
xcrun notarytool submit "$app_zip" "${notary_args[@]}" --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

SIGNING_IDENTITY="$SIGNING_IDENTITY" SIGNING_KEYCHAIN="$SIGNING_KEYCHAIN" \
  NTFSMAC_DMG_OUT="$DMG" "$SCRIPT_DIR/make-dmg.sh"
xcrun notarytool submit "$DMG" "${notary_args[@]}" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

RELEASE_VERSION="$VERSION" SIGNING_IDENTITY="$SIGNING_IDENTITY" REQUIRE_NOTARIZATION=1 \
  NTFSMAC_APP_BUNDLE="$APP" NTFSMAC_DMG_OUT="$DMG" "$SCRIPT_DIR/verify-release.sh"

echo "notarize-release: complete — $DMG"
