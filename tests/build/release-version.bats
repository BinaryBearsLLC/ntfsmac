#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  RESOLVER="$REPO_ROOT/build/lib/release-version.sh"
  PLIST="$BATS_TEST_TMPDIR/Info.plist"
  /usr/libexec/PlistBuddy -c 'Add :CFBundleShortVersionString string 3.1.3' "$PLIST"
}

@test "stable metadata resolves without a prerelease suffix" {
  run bash "$RESOLVER" "$PLIST"
  [ "$status" -eq 0 ]
  [ "$output" = 3.1.3 ]
}

@test "beta tag requires a matching human label" {
  /usr/libexec/PlistBuddy -c 'Add :NTFSMACReleaseTag string 3.1.3-beta.1' "$PLIST"
  run bash "$RESOLVER" "$PLIST"
  [ "$status" -ne 0 ]
  /usr/libexec/PlistBuddy -c 'Add :NTFSMACReleaseLabel string Beta 1' "$PLIST"
  run bash "$RESOLVER" "$PLIST"
  [ "$status" -eq 0 ]
  [ "$output" = 3.1.3-beta.1 ]
}

@test "beta cannot mismatch the numeric version or use invalid numbering" {
  /usr/libexec/PlistBuddy -c 'Add :NTFSMACReleaseTag string 3.1.4-beta.1' "$PLIST"
  /usr/libexec/PlistBuddy -c 'Add :NTFSMACReleaseLabel string Beta 1' "$PLIST"
  run bash "$RESOLVER" "$PLIST"
  [ "$status" -ne 0 ]
  /usr/libexec/PlistBuddy -c 'Set :NTFSMACReleaseTag 3.1.3-beta.01' "$PLIST"
  run bash "$RESOLVER" "$PLIST"
  [ "$status" -ne 0 ]
}
