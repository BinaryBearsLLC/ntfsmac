#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  source "$REPO_ROOT/build/lib/macos-target.sh"
}

@test "deployment target does not inherit the newer build host" {
  export MACOSX_DEPLOYMENT_TARGET=26.0
  macos_target_activate
  [ "$MACOSX_DEPLOYMENT_TARGET" = 14.0 ]
}

@test "Sonoma gate accepts older or exact 14.0 minimums" {
  for version in 11.0 13.0 14.0 14.0.0; do
    run bash -c 'source "$1"; printf "platform MACOS\nminos %s\n" "$2" | macos_target_check_metadata' _ \
      "$REPO_ROOT/build/lib/macos-target.sh" "$version"
    [ "$status" -eq 0 ]
  done
}

@test "Sonoma gate rejects newer patch minor and major minimums" {
  for version in 14.0.1 14.1 15.0 26.0; do
    run bash -c 'source "$1"; printf "platform MACOS\nminos %s\n" "$2" | macos_target_check_metadata' _ \
      "$REPO_ROOT/build/lib/macos-target.sh" "$version"
    [ "$status" -ne 0 ]
  done
}

@test "Sonoma gate fails closed on absent malformed duplicate or non-macOS metadata" {
  for metadata in '' 'minos 14.0' $'platform MACOS\nminos invalid' \
    $'platform IOS\nminos 14.0' $'platform MACOS\nminos 14.0\nminos 14.0'; do
    run bash -c 'source "$1"; printf "%s\n" "$2" | macos_target_check_metadata' _ \
      "$REPO_ROOT/build/lib/macos-target.sh" "$metadata"
    [ "$status" -ne 0 ]
  done
}

@test "Sonoma gate refuses a non-Mach-O file" {
  run macos_target_verify_binary "$REPO_ROOT/gui/Info.plist"
  [ "$status" -ne 0 ]
}

@test "GUI package minimum matches the shipping floor" {
  run /usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$REPO_ROOT/gui/Info.plist"
  [ "$output" = 14.0 ]
  run grep -F 'platforms: [.macOS(.v14)]' "$REPO_ROOT/Package.swift"
  [ "$status" -eq 0 ]
}

@test "Sonoma gate inspects real Mach-O load commands and catches host-target leakage" {
  for version in 14.0 26.0; do
    run xcrun clang -dynamiclib -x c /dev/null -arch arm64 \
      "-mmacosx-version-min=$version" -o "$BATS_TEST_TMPDIR/probe-$version.dylib"
    [ "$status" -eq 0 ]
    run macos_target_verify_binary "$BATS_TEST_TMPDIR/probe-$version.dylib"
    if [ "$version" = 14.0 ]; then
      [ "$status" -eq 0 ]
    else
      [ "$status" -ne 0 ]
    fi
  done
}
