#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  NOTARIZE_SCRIPT="$REPO_ROOT/build/notarize-release.sh"
  VERIFY_SCRIPT="$REPO_ROOT/build/verify-release.sh"
  RELEASE_WORKFLOW="$REPO_ROOT/.github/workflows/release.yml"
}

@test "official release build defaults to standard and Legacy artifacts" {
  run grep -F 'INCLUDE_LEGACY_RAW="${INCLUDE_LEGACY:-1}"' "$NOTARIZE_SCRIPT"
  [ "$status" -eq 0 ]
  run grep -F 'build_notarized_variant modern' "$NOTARIZE_SCRIPT"
  [ "$status" -eq 0 ]
  run grep -F 'build_notarized_variant legacy' "$NOTARIZE_SCRIPT"
  [ "$status" -eq 0 ]
}

@test "release workflow exposes the Legacy opt-out but defaults it on" {
  run grep -F 'include_legacy:' "$RELEASE_WORKFLOW"
  [ "$status" -eq 0 ]
  run grep -F 'default: true' "$RELEASE_WORKFLOW"
  [ "$status" -eq 0 ]
  run grep -F 'Legacy-Apple-Silicon.dmg' "$RELEASE_WORKFLOW"
  [ "$status" -eq 0 ]
}

@test "release verifier checks the selected app and DMG variant" {
  run grep -F 'NTFSMACHelperVariant' "$VERIFY_SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *'DMG'* || "$output" == *'plist_value'* ]]
  run grep -F 'com.binarybears.ntfsmac.helper.daemon' "$VERIFY_SCRIPT"
  [ "$status" -eq 0 ]
  run grep -F 'com.binarybears.ntfsmac.helper' "$VERIFY_SCRIPT"
  [ "$status" -eq 0 ]
  run grep -F 'website.filename' "$VERIFY_SCRIPT"
  [ "$status" -eq 0 ]
  run grep -F 'com.apple.ResourceFork' "$VERIFY_SCRIPT"
  [ "$status" -eq 0 ]
  run grep -F '.background/ntfsmac-dmg-background.png' "$VERIFY_SCRIPT"
  [ "$status" -eq 0 ]
  run grep -F 'write-sha256.sh' "$VERIFY_SCRIPT"
  [ "$status" -eq 0 ]
}

@test "all three product plists carry the same candidate version" {
  local app_version legacy_version modern_version
  app_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$REPO_ROOT/gui/Info.plist")"
  legacy_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$REPO_ROOT/helper/Info.plist")"
  modern_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$REPO_ROOT/helper/Info-Modern.plist")"
  [ "$app_version" = "$legacy_version" ]
  [ "$app_version" = "$modern_version" ]
  [ "$app_version" = "3.1.0" ]
}
