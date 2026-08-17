#!/bin/bash
# Verify the exact app and DMG intended for a BinaryBears release.
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." &>/dev/null && pwd)"
APP="${NTFSMAC_APP_BUNDLE:-$REPO_ROOT/dist/ntfsmac.app}"
VERSION="${RELEASE_VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$REPO_ROOT/gui/Info.plist")}"
DMG="${NTFSMAC_DMG_OUT:-$REPO_ROOT/dist/ntfsmac-${VERSION}-Apple-Silicon.dmg}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
REQUIRE_NOTARIZATION="${REQUIRE_NOTARIZATION:-0}"

fail() {
  echo "verify-release: FAIL — $*" >&2
  exit 1
}

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$2" "$1"
}

require_arm64_only() {
  local path="$1" arches
  arches="$(lipo -archs "$path" 2>/dev/null)" || fail "$path is not a Mach-O executable"
  [[ "$arches" == "arm64" ]] || fail "$path has architecture '$arches', expected arm64"
}

verify_app() {
  [[ -d "$APP" ]] || fail "app bundle missing: $APP"
  [[ "$(plist_value "$APP/Contents/Info.plist" CFBundleIdentifier)" == "com.binarybears.ntfsmac" ]] ||
    fail "unexpected app bundle identifier"
  [[ "$(plist_value "$APP/Contents/Info.plist" CFBundleName)" == "ntfsmac" ]] ||
    fail "visible app name is not ntfsmac"
  [[ "$(plist_value "$APP/Contents/Info.plist" CFBundleShortVersionString)" == "$VERSION" ]] ||
    fail "app version does not match $VERSION"

  local app_bin="$APP/Contents/MacOS/ntfsmac-gui"
  local helper="$APP/Contents/Library/LaunchServices/com.binarybears.ntfsmac.helper"
  [[ -f "$helper" ]] || fail "BinaryBears helper is missing"
  require_arm64_only "$app_bin"
  require_arm64_only "$helper"

  codesign --verify --deep --strict --verbose=2 "$APP" || fail "app signature verification failed"
  local app_info helper_info
  app_info="$(codesign -dvvv "$APP" 2>&1)"
  helper_info="$(codesign -dvvv "$helper" 2>&1)"
  [[ "$app_info" == *"Identifier=com.binarybears.ntfsmac"* ]] || fail "signed app identifier is wrong"
  [[ "$helper_info" == *"Identifier=com.binarybears.ntfsmac.helper"* ]] || fail "signed helper identifier is wrong"

  NTFSMAC_VENDOR_BIN_DIR="$APP/Contents/Resources/cli-src/vendor/bin" \
    SIGNING_IDENTITY="$SIGNING_IDENTITY" "$SCRIPT_DIR/verify-signature.sh" ||
    fail "nested runtime signature verification failed"

  if [[ "$SIGNING_IDENTITY" != "-" ]]; then
    [[ "$app_info" == *"Authority=$SIGNING_IDENTITY"* && "$app_info" == *"TeamIdentifier=SQY8T23X8N"* ]] ||
      fail "app is not signed by BinaryBears"
    [[ "$helper_info" == *"Authority=$SIGNING_IDENTITY"* && "$helper_info" == *"TeamIdentifier=SQY8T23X8N"* ]] ||
      fail "helper is not signed by BinaryBears"
  fi

  if [[ "$REQUIRE_NOTARIZATION" == "1" ]]; then
    xcrun stapler validate "$APP" || fail "app has no valid stapled ticket"
    spctl --assess --type execute --verbose=4 "$APP" || fail "Gatekeeper rejected the app"
  fi
}

verify_dmg() {
  [[ -f "$DMG" ]] || fail "DMG missing: $DMG"
  hdiutil verify "$DMG" >/dev/null || fail "DMG container verification failed"

  local mount_dir
  mount_dir="$(mktemp -d)"
  # Expand the path now: an EXIT trap runs after this function's locals are out of scope.
  # shellcheck disable=SC2064
  trap "hdiutil detach '$mount_dir' -quiet >/dev/null 2>&1 || true; rmdir '$mount_dir' >/dev/null 2>&1 || true" EXIT
  hdiutil attach "$DMG" -mountpoint "$mount_dir" -nobrowse -readonly -noautoopen >/dev/null ||
    fail "DMG could not be mounted"
  [[ -d "$mount_dir/ntfsmac.app" ]] || fail "DMG does not contain ntfsmac.app"
  [[ -L "$mount_dir/Applications" && "$(readlink "$mount_dir/Applications")" == "/Applications" ]] ||
    fail "DMG Applications link is missing or invalid"
  [[ -f "$mount_dir/.VolumeIcon.icns" ]] || fail "DMG does not contain the approved volume icon"
  [[ "$(plist_value "$mount_dir/ntfsmac.app/Contents/Info.plist" CFBundleIdentifier)" == "com.binarybears.ntfsmac" ]] ||
    fail "DMG contains the wrong app bundle"
  hdiutil detach "$mount_dir" -quiet
  rmdir "$mount_dir"
  trap - EXIT

  if [[ "$SIGNING_IDENTITY" != "-" ]]; then
    local dmg_info
    dmg_info="$(codesign -dvvv "$DMG" 2>&1)"
    [[ "$dmg_info" == *"Authority=$SIGNING_IDENTITY"* && "$dmg_info" == *"TeamIdentifier=SQY8T23X8N"* ]] ||
      fail "DMG is not signed by BinaryBears"
  fi
  if [[ "$REQUIRE_NOTARIZATION" == "1" ]]; then
    xcrun stapler validate "$DMG" || fail "DMG has no valid stapled ticket"
    spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG" ||
      fail "Gatekeeper rejected the DMG"
  fi

  (
    cd "$(dirname "$DMG")"
    shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256"
    shasum -a 256 -c "$(basename "$DMG").sha256" >/dev/null
  ) || fail "checksum verification failed"
}

verify_app
verify_dmg
echo "verify-release: OK — ntfsmac $VERSION"
