#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  APP="$BATS_TEST_TMPDIR/ntfsmac.app"
  mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Library/LaunchDaemons"
  cp "$REPO_ROOT/gui/Info.plist" "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c 'Set :NTFSMACHelperVariant modern' "$APP/Contents/Info.plist" 2>/dev/null ||
    /usr/libexec/PlistBuddy -c 'Add :NTFSMACHelperVariant string modern' "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c 'Delete :SMPrivilegedExecutables' "$APP/Contents/Info.plist" 2>/dev/null || true
  cp "$REPO_ROOT/helper/launchd-modern.plist" \
    "$APP/Contents/Library/LaunchDaemons/com.binarybears.ntfsmac.helper.daemon.plist"
  printf 'int main(void) { return 0; }\n' | \
    clang -arch arm64 -mmacosx-version-min=14.0 -x c - -o "$APP/Contents/Resources/ntfsmac-helper"
}

@test "release gate rejects a macOS 26 GUI before signature or DMG checks" {
  printf 'int main(void) { return 0; }\n' | \
    clang -arch arm64 -mmacosx-version-min=26.0 -x c - -o "$APP/Contents/MacOS/ntfsmac-gui"
  run env NTFSMAC_APP_BUNDLE="$APP" SIGNING_IDENTITY=- "$REPO_ROOT/build/verify-release.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"GUI exceeds the macOS 14 floor"* ]]
}

@test "release gate rejects a manifest above the macOS 14 floor" {
  /usr/libexec/PlistBuddy -c 'Set :LSMinimumSystemVersion 26.0' "$APP/Contents/Info.plist"
  run env NTFSMAC_APP_BUNDLE="$APP" SIGNING_IDENTITY=- "$REPO_ROOT/build/verify-release.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"app must declare the macOS 14.0 floor"* ]]
}
