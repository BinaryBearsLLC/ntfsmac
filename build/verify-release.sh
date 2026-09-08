#!/bin/bash
# Verify the exact app and DMG intended for a BinaryBears release.
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." &>/dev/null && pwd)"
# shellcheck source=build/lib/macos-target.sh
source "$SCRIPT_DIR/lib/macos-target.sh"
APP="${NTFSMAC_APP_BUNDLE:-$REPO_ROOT/dist/ntfsmac.app}"
VERSION="${RELEASE_VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$REPO_ROOT/gui/Info.plist")}"
DMG="${NTFSMAC_DMG_OUT:-$REPO_ROOT/dist/ntfsmac-${VERSION}-Apple-Silicon.dmg}"
HELPER_VARIANT="${NTFSMAC_HELPER_VARIANT:-modern}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
REQUIRE_NOTARIZATION="${REQUIRE_NOTARIZATION:-0}"
LAYOUT_CONFIG="${NTFSMAC_DMG_LAYOUT:-$REPO_ROOT/build/dmg-assets/layout.json}"

fail() {
  echo "verify-release: FAIL — $*" >&2
  exit 1
}

case "$HELPER_VARIANT" in
  modern | legacy) ;;
  *) fail "unknown helper variant: $HELPER_VARIANT" ;;
esac

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
  [[ "$(plist_value "$APP/Contents/Info.plist" LSMinimumSystemVersion)" == "14.0" ]] ||
    fail "app must declare the macOS 14.0 floor"

  [[ "$(plist_value "$APP/Contents/Info.plist" NTFSMACHelperVariant)" == "$HELPER_VARIANT" ]] ||
    fail "app helper variant does not match $HELPER_VARIANT"

  local app_bin="$APP/Contents/MacOS/ntfsmac-gui" helper helper_identifier
  if [[ "$HELPER_VARIANT" == "modern" ]]; then
    helper="$APP/Contents/Resources/ntfsmac-helper"
    helper_identifier="com.binarybears.ntfsmac.helper.daemon"
    local daemon_plist="$APP/Contents/Library/LaunchDaemons/${helper_identifier}.plist"
    [[ -f "$daemon_plist" ]] || fail "SMAppService LaunchDaemon plist is missing"
    [[ "$(plist_value "$daemon_plist" Label)" == "$helper_identifier" ]] ||
      fail "SMAppService LaunchDaemon label is wrong"
    [[ "$(plist_value "$daemon_plist" BundleProgram)" == "Contents/Resources/ntfsmac-helper" ]] ||
      fail "SMAppService BundleProgram is wrong"
    ! /usr/libexec/PlistBuddy -c 'Print :SMPrivilegedExecutables' "$APP/Contents/Info.plist" >/dev/null 2>&1 ||
      fail "standard app still declares SMPrivilegedExecutables"
  else
    helper_identifier="com.binarybears.ntfsmac.helper"
    helper="$APP/Contents/Library/LaunchServices/$helper_identifier"
    [[ "$(plist_value "$APP/Contents/Info.plist" "SMPrivilegedExecutables:$helper_identifier")" == \
      "identifier \"$helper_identifier\"" ]] || fail "Legacy SMJobBless trust pairing is wrong"
  fi
  [[ -f "$helper" ]] || fail "BinaryBears helper is missing"
  require_arm64_only "$app_bin"
  require_arm64_only "$helper"
  macos_target_verify_binary "$app_bin" || fail "GUI exceeds the macOS 14 floor"
  macos_target_verify_binary "$helper" || fail "helper exceeds the macOS 14 floor"
  macos_target_verify_runtime "$APP/Contents/Resources/cli-src/vendor/bin" ||
    fail "bundled runtime exceeds the macOS 14 floor"

  codesign --verify --deep --strict --verbose=2 "$APP" || fail "app signature verification failed"
  local app_info helper_info
  app_info="$(codesign -dvvv "$APP" 2>&1)"
  helper_info="$(codesign -dvvv "$helper" 2>&1)"
  [[ "$app_info" == *"Identifier=com.binarybears.ntfsmac"* ]] || fail "signed app identifier is wrong"
  [[ "$helper_info" == *"Identifier=$helper_identifier"* ]] || fail "signed helper identifier is wrong"

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
  local website_filename
  website_filename="$(/usr/bin/plutil -extract website.filename raw "$LAYOUT_CONFIG" 2>/dev/null)" ||
    fail "DMG layout configuration is unreadable"
  [[ -f "$mount_dir/$website_filename" ]] ||
    fail "DMG does not contain the BinaryBears website link"
  [[ "$(/usr/bin/plutil -extract URL raw "$mount_dir/$website_filename" 2>/dev/null)" == \
    "https://binarybears.com/" ]] || fail "DMG website link has the wrong destination"
  xattr -p com.apple.ResourceFork "$mount_dir/$website_filename" >/dev/null 2>&1 ||
    fail "DMG website link has no custom BinaryBears icon"
  [[ -f "$mount_dir/.DS_Store" ]] || fail "DMG Finder layout is missing"
  [[ -f "$mount_dir/.background/ntfsmac-dmg-background.png" ]] ||
    fail "DMG branded background is missing"
  local background_info
  background_info="$(sips -g pixelWidth -g pixelHeight \
    "$mount_dir/.background/ntfsmac-dmg-background.png" 2>/dev/null)" ||
    fail "DMG branded background is unreadable"
  [[ "$background_info" == *"pixelWidth: 720"* && \
    "$background_info" == *"pixelHeight: 460"* ]] ||
    fail "DMG branded background has the wrong canvas size"
  [[ -f "$mount_dir/.VolumeIcon.icns" ]] || fail "DMG does not contain the approved volume icon"
  [[ "$(plist_value "$mount_dir/ntfsmac.app/Contents/Info.plist" CFBundleIdentifier)" == "com.binarybears.ntfsmac" ]] ||
    fail "DMG contains the wrong app bundle"
  [[ "$(plist_value "$mount_dir/ntfsmac.app/Contents/Info.plist" NTFSMACHelperVariant)" == "$HELPER_VARIANT" ]] ||
    fail "DMG contains the wrong helper variant"
  # Validate the delivered copy, not only the separate app used as packaging input.
  # Bash dynamic scope keeps this path confined to the mounted-image check.
  local APP="$mount_dir/ntfsmac.app"
  verify_app
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

  "$SCRIPT_DIR/write-sha256.sh" "$DMG" || fail "checksum verification failed"
}

verify_app
verify_dmg
echo "verify-release: OK — ntfsmac $VERSION ($HELPER_VARIANT)"
