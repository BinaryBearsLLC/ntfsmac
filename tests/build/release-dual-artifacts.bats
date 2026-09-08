#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  NOTARIZE_SCRIPT="$REPO_ROOT/build/notarize-release.sh"
  VERIFY_SCRIPT="$REPO_ROOT/build/verify-release.sh"
  RELEASE_WORKFLOW="$REPO_ROOT/.github/workflows/release.yml"
}

@test "official release builds only the Standard artifact" {
  run grep -F 'build_notarized_variant modern' "$NOTARIZE_SCRIPT"
  [ "$status" -eq 0 ]
  run grep -F 'build_notarized_variant legacy' "$NOTARIZE_SCRIPT"
  [ "$status" -eq 1 ]
}

@test "obsolete Legacy release request fails before credentials or build" {
  run env -u SIGNING_IDENTITY -u NOTARY_PROFILE INCLUDE_LEGACY=true "$NOTARIZE_SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Standard only"* ]]
  [[ "$output" != *"Set SIGNING_IDENTITY"* ]]
}

@test "release workflow publishes only the Standard DMG and checksum" {
  run grep -F 'include_legacy:' "$RELEASE_WORKFLOW"
  [ "$status" -eq 1 ]
  run grep -F 'Legacy-Apple-Silicon.dmg' "$RELEASE_WORKFLOW"
  [ "$status" -eq 1 ]
  run grep -F 'assets=("$dmg_path" "${dmg_path}.sha256")' "$RELEASE_WORKFLOW"
  [ "$status" -eq 0 ]
}

@test "release orchestration selects Standard only and preserves historical artifacts (mocked tools)" {
  local fixture="$BATS_TEST_TMPDIR/release" mock_bin="$BATS_TEST_TMPDIR/bin" step
  mkdir -p "$fixture/build/lib" "$fixture/gui" "$fixture/dist/ntfsmac-legacy.app" "$mock_bin"
  cp "$REPO_ROOT/build/lib/release-version.sh" "$fixture/build/lib/"
  cp "$NOTARIZE_SCRIPT" "$fixture/build/notarize-release.sh"
  cp "$REPO_ROOT/gui/Info.plist" "$fixture/gui/Info.plist"
  printf 'historical artifact\n' > "$fixture/dist/ntfsmac-3.1.3-Legacy-Apple-Silicon.dmg"
  printf 'historical app\n' > "$fixture/dist/ntfsmac-legacy.app/sentinel"
  # No real build, credentials, signing, network submission, or image operation.
  cat > "$mock_bin/record" <<'SH'
#!/bin/bash
set -eu
printf '%s|%s|%s|%s\n' "${0##*/}" "${NTFSMAC_HELPER_VARIANT:-}" "${NTFSMAC_DMG_OUT:-}" "$*" >> "$TEST_RELEASE_TRACE"
SH
  chmod +x "$mock_bin/record"
  for step in sync-brand-assets.sh build-all.sh sign.sh package-app.sh make-dmg.sh verify-release.sh; do
    cp "$mock_bin/record" "$fixture/build/$step"
  done
  for step in xcrun ditto; do
    cp "$mock_bin/record" "$mock_bin/$step"
  done
  run env PATH="$mock_bin:$PATH" TEST_RELEASE_TRACE="$BATS_TEST_TMPDIR/trace" \
    SIGNING_IDENTITY='Developer ID Application: BinaryBears LLC (SQY8T23X8N)' \
    NOTARY_PROFILE=mock-only INCLUDE_LEGACY=0 \
    "$fixture/build/notarize-release.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Standard only"* ]]
  [ "$(grep -c '^package-app.sh|modern|' "$BATS_TEST_TMPDIR/trace")" -eq 1 ]
  [ "$(grep -c '^make-dmg.sh|' "$BATS_TEST_TMPDIR/trace")" -eq 1 ]
  [ "$(grep -c '^verify-release.sh|modern|' "$BATS_TEST_TMPDIR/trace")" -eq 1 ]
  [ "$(grep -c 'notarytool submit' "$BATS_TEST_TMPDIR/trace")" -eq 2 ]
  ! grep -E 'Legacy|\|legacy\|' "$BATS_TEST_TMPDIR/trace"
  [ "$(< "$fixture/dist/ntfsmac-legacy.app/sentinel")" = 'historical app' ]
  [ "$(< "$fixture/dist/ntfsmac-3.1.3-Legacy-Apple-Silicon.dmg")" = 'historical artifact' ]
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
  [ "$app_version" = "3.1.3" ]
}
