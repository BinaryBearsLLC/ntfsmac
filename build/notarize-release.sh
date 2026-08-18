#!/bin/bash
# Build, Developer ID sign, notarize, staple, and verify an official release candidate.
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." &>/dev/null && pwd)"
SIGNING_IDENTITY="${SIGNING_IDENTITY:?Set SIGNING_IDENTITY to the BinaryBears Developer ID Application identity}"
SIGNING_KEYCHAIN="${SIGNING_KEYCHAIN:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:?Set NOTARY_PROFILE to a notarytool Keychain profile}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$REPO_ROOT/gui/Info.plist")"
INCLUDE_LEGACY_RAW="${INCLUDE_LEGACY:-1}"
case "$INCLUDE_LEGACY_RAW" in
  1 | true | TRUE | yes | YES) INCLUDE_LEGACY_BUILD=1 ;;
  0 | false | FALSE | no | NO) INCLUDE_LEGACY_BUILD=0 ;;
  *)
    echo "notarize-release: HARD-STOP — INCLUDE_LEGACY must be true/false or 1/0" >&2
    exit 1
    ;;
esac

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

build_notarized_variant() {
  local variant="$1" app="$2" dmg="$3" volume_name="$4"
  local app_zip

  NTFSMAC_HELPER_VARIANT="$variant" NTFSMAC_APP_BUNDLE_OUT="$app" \
    SIGNING_IDENTITY="$SIGNING_IDENTITY" SIGNING_KEYCHAIN="$SIGNING_KEYCHAIN" \
    "$SCRIPT_DIR/package-app.sh"

  app_zip="$NOTARY_TEMP_DIR/ntfsmac-${variant}.app.zip"
  ditto -c -k --keepParent "$app" "$app_zip"
  xcrun notarytool submit "$app_zip" "${notary_args[@]}" --wait
  rm -f "$app_zip"
  xcrun stapler staple "$app"
  xcrun stapler validate "$app"

  NTFSMAC_APP_BUNDLE="$app" NTFSMAC_DMG_OUT="$dmg" \
    NTFSMAC_DMG_VOLUME_NAME="$volume_name" \
    SIGNING_IDENTITY="$SIGNING_IDENTITY" SIGNING_KEYCHAIN="$SIGNING_KEYCHAIN" \
    "$SCRIPT_DIR/make-dmg.sh"
  xcrun notarytool submit "$dmg" "${notary_args[@]}" --wait
  xcrun stapler staple "$dmg"
  xcrun stapler validate "$dmg"

  RELEASE_VERSION="$VERSION" NTFSMAC_HELPER_VARIANT="$variant" \
    SIGNING_IDENTITY="$SIGNING_IDENTITY" REQUIRE_NOTARIZATION=1 \
    NTFSMAC_APP_BUNDLE="$app" NTFSMAC_DMG_OUT="$dmg" "$SCRIPT_DIR/verify-release.sh"
}

NOTARY_TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$NOTARY_TEMP_DIR"' EXIT

MODERN_APP="$REPO_ROOT/dist/ntfsmac.app"
MODERN_DMG="$REPO_ROOT/dist/ntfsmac-${VERSION}-Apple-Silicon.dmg"
LEGACY_APP="$REPO_ROOT/dist/ntfsmac-legacy.app"
LEGACY_DMG="$REPO_ROOT/dist/ntfsmac-${VERSION}-Legacy-Apple-Silicon.dmg"
build_notarized_variant modern "$MODERN_APP" "$MODERN_DMG" "ntfsmac Installer"

if [[ "$INCLUDE_LEGACY_BUILD" -eq 1 ]]; then
  build_notarized_variant legacy "$LEGACY_APP" "$LEGACY_DMG" "ntfsmac Legacy Installer"
  echo "notarize-release: complete — $MODERN_DMG and $LEGACY_DMG"
else
  rm -rf -- "$LEGACY_APP"
  rm -f -- "$LEGACY_DMG" "${LEGACY_DMG}.sha256"
  echo "notarize-release: complete — $MODERN_DMG (Legacy disabled)"
fi
