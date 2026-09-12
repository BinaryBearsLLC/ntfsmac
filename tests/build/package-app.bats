#!/usr/bin/env bats
# tests/build/package-app.bats — build/package-app.sh acceptance checks.
#
# Assembles the standard SMAppService app or the Legacy SMJobBless app from the same source.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SCRIPT="$REPO_ROOT/build/package-app.sh"

  RELEASE_DIR="$(mktemp -d)"
  OUT_DIR="$(mktemp -d)"

  # Real Mach-O fixtures (codesign needs a real binary) standing in for the swift-build
  # release output, named exactly what `swift build -c release` would produce.
  local mock_c="$(mktemp).c"
  printf '#include <stdio.h>\n#include <string.h>\nint main(int argc, char **argv) {\n  if (argc > 1 && strcmp(argv[1], "--print-tree-hash") == 0) {\n    printf("mocktreehash1234567890abcdef123\\n");\n  }\n  return 0;\n}\n' > "$mock_c"
  clang -arch arm64 -mmacosx-version-min=14.0 "$mock_c" -o "$RELEASE_DIR/ntfsmac-helper"
  cp "$RELEASE_DIR/ntfsmac-helper" "$RELEASE_DIR/ntfsmac-gui"
  rm -f "$mock_c"
  chmod +x "$RELEASE_DIR/ntfsmac-gui" "$RELEASE_DIR/ntfsmac-helper"

  export NTFSMAC_SWIFT_RELEASE_DIR="$RELEASE_DIR"
  export NTFSMAC_APP_OUT_DIR="$OUT_DIR"
  export NTFSMAC_SKIP_SWIFT_BUILD=1
  APP="$OUT_DIR/ntfsmac.app"
}

teardown() {
  rm -rf "$RELEASE_DIR" "$OUT_DIR"
}

@test "package-app.sh exists and is executable" {
  [ -x "$SCRIPT" ]
}

@test "package-app rejects a GUI compiled above the macOS 14 floor" {
  printf 'int main(void) { return 0; }\n' | \
    clang -arch arm64 -mmacosx-version-min=26.0 -x c - -o "$RELEASE_DIR/ntfsmac-gui"
  run "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"minimum exceeds 14.0"* ]]
}

@test "assembles the standard app with an embedded SMAppService LaunchDaemon" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -d "$APP" ]
  [ -f "$APP/Contents/Info.plist" ]
  [ -f "$APP/Contents/MacOS/ntfsmac-gui" ]
  [ -f "$APP/Contents/Resources/AppIcon.icns" ]
  [ -f "$APP/Contents/Resources/HelperIcon.png" ]
  [ -f "$APP/Contents/Resources/cli-src/cli/pf/ntfsmac.anchor.tmpl" ]
  [ -f "$APP/Contents/Resources/cli-src/vendor/runtime/SHA256SUMS" ]
  [ -f "$APP/Contents/Resources/cli-src/vendor/runtime/oci/index.json" ]
  [ -f "$APP/Contents/Resources/cli-src/build/verify-offline-runtime.py" ]
  run python3 "$APP/Contents/Resources/cli-src/build/verify-offline-runtime.py" \
    "$APP/Contents/Resources/cli-src"
  [ "$status" -eq 0 ]
  [ -f "$APP/Contents/Resources/ntfsmac-helper" ]
  [ -f "$APP/Contents/Library/LaunchDaemons/com.binarybears.ntfsmac.helper.daemon.plist" ]
  run /usr/libexec/PlistBuddy -c "Print :BundleProgram" \
    "$APP/Contents/Library/LaunchDaemons/com.binarybears.ntfsmac.helper.daemon.plist"
  [ "$output" = "Contents/Resources/ntfsmac-helper" ]
  run /usr/libexec/PlistBuddy -c "Print :NTFSMACHelperVariant" "$APP/Contents/Info.plist"
  [ "$output" = "modern" ]
  run /usr/libexec/PlistBuddy -c "Print :SMPrivilegedExecutables" "$APP/Contents/Info.plist"
  [ "$status" -ne 0 ]
}

@test "offline payload staging rejects corruption without publishing a partial runtime" {
  local fixture_root stage_root
  fixture_root="$BATS_TEST_TMPDIR/corrupt-package-source"
  stage_root="$BATS_TEST_TMPDIR/package-stage"
  mkdir -p "$fixture_root/build" "$fixture_root/vendor" "$stage_root"
  cp "$REPO_ROOT/build/verify-offline-runtime.py" "$fixture_root/build/"
  cp "$REPO_ROOT/build/sources.lock" "$REPO_ROOT/build/alpine-base-packages.lock" \
    "$REPO_ROOT/build/alpine-packages.lock" "$REPO_ROOT/build/alpine-apks.lock" "$fixture_root/build/"
  cp -R "$REPO_ROOT/vendor/runtime" "$fixture_root/vendor/runtime"
  printf 'tampered\n' >> "$fixture_root/vendor/runtime/entrypoint.sh"

  run bash -c 'source "$1"; stage_offline_runtime "$2" "$3"' \
    _ "$SCRIPT" "$fixture_root" "$stage_root"

  [ "$status" -ne 0 ]
  [[ "$output" == *"HARD-STOP"* ]]
  [ ! -e "$stage_root/vendor/runtime" ]
}

@test "offline payload staging produces a self-verifying copy of the complete runtime" {
  local stage_root
  stage_root="$BATS_TEST_TMPDIR/verified-package-stage"
  mkdir -p "$stage_root"

  run bash -c 'source "$1"; stage_offline_runtime "$2" "$3"' \
    _ "$SCRIPT" "$REPO_ROOT" "$stage_root"

  [ "$status" -eq 0 ]
  run python3 "$stage_root/build/verify-offline-runtime.py" "$stage_root"
  [ "$status" -eq 0 ]
  run diff -qr "$REPO_ROOT/vendor/runtime" "$stage_root/vendor/runtime"
  [ "$status" -eq 0 ]
}

@test "native packaging gate rejects a payload whose updated locks exceed the embedded manifest" {
  local stage_root license_sha manifest_sha
  stage_root="$BATS_TEST_TMPDIR/stale-native-manifest-stage"
  mkdir -p "$stage_root/build" "$stage_root/vendor/bin"
  cp "$REPO_ROOT/build/verify-offline-runtime.py" "$stage_root/build/"
  cp "$REPO_ROOT/build/sources.lock" "$REPO_ROOT/build/alpine-base-packages.lock" \
    "$REPO_ROOT/build/alpine-packages.lock" "$REPO_ROOT/build/alpine-apks.lock" "$stage_root/build/"
  cp "$REPO_ROOT/vendor/bin/init-rootfs" "$stage_root/vendor/bin/init-rootfs"
  cp -R "$REPO_ROOT/vendor/runtime" "$stage_root/vendor/runtime"

  printf '\nfixture revision\n' >> "$stage_root/vendor/runtime/LICENSE.nfs-entrypoint"
  license_sha="$(shasum -a 256 "$stage_root/vendor/runtime/LICENSE.nfs-entrypoint" | awk '{print $1}')"
  awk -v sha="$license_sha" 'BEGIN { OFS="  " } $2 == "LICENSE.nfs-entrypoint" { $1=sha } { print $1, $2 }' \
    "$stage_root/vendor/runtime/SHA256SUMS" > "$stage_root/vendor/runtime/SHA256SUMS.new"
  mv "$stage_root/vendor/runtime/SHA256SUMS.new" "$stage_root/vendor/runtime/SHA256SUMS"
  manifest_sha="$(shasum -a 256 "$stage_root/vendor/runtime/SHA256SUMS" | awk '{print $1}')"
  awk -v sha="$manifest_sha" 'BEGIN { FS=OFS="=" } $1 == "OFFLINE_RUNTIME_SHA256" { $2=sha } { print }' \
    "$stage_root/build/sources.lock" > "$stage_root/build/sources.lock.new"
  mv "$stage_root/build/sources.lock.new" "$stage_root/build/sources.lock"

  run python3 "$stage_root/build/verify-offline-runtime.py" "$stage_root"
  [ "$status" -eq 0 ]
  run bash -c 'source "$1"; verify_staged_native_offline_runtime "$2"' \
    _ "$SCRIPT" "$stage_root"
  [ "$status" -ne 0 ]
  [[ "$output" == *"embedded offline runtime manifest"* ]]
}

@test "offline payload staging rejects a missing source without publishing a partial runtime" {
  local fixture_root stage_root
  fixture_root="$BATS_TEST_TMPDIR/missing-package-source"
  stage_root="$BATS_TEST_TMPDIR/missing-package-stage"
  mkdir -p "$fixture_root/build" "$fixture_root/vendor" "$stage_root"
  cp "$REPO_ROOT/build/verify-offline-runtime.py" "$fixture_root/build/"
  cp "$REPO_ROOT/build/sources.lock" "$REPO_ROOT/build/alpine-base-packages.lock" \
    "$REPO_ROOT/build/alpine-packages.lock" "$REPO_ROOT/build/alpine-apks.lock" "$fixture_root/build/"

  run bash -c 'source "$1"; stage_offline_runtime "$2" "$3"' \
    _ "$SCRIPT" "$fixture_root" "$stage_root"

  [ "$status" -ne 0 ]
  [[ "$output" == *"HARD-STOP"* ]]
  [ ! -e "$stage_root/vendor/runtime" ]
}

@test "assembles the Legacy app with the SMJobBless trust pairing" {
  NTFSMAC_HELPER_VARIANT=legacy run "$SCRIPT"
  [ "$status" -eq 0 ]
  local legacy_app="$OUT_DIR/ntfsmac-legacy.app"
  [ -f "$legacy_app/Contents/Library/LaunchServices/com.binarybears.ntfsmac.helper" ]
  [ ! -d "$legacy_app/Contents/Library/LaunchDaemons" ]
  run /usr/libexec/PlistBuddy -c "Print :NTFSMACHelperVariant" "$legacy_app/Contents/Info.plist"
  [ "$output" = "legacy" ]
  run /usr/libexec/PlistBuddy -c "Print :SMPrivilegedExecutables:com.binarybears.ntfsmac.helper" \
    "$legacy_app/Contents/Info.plist"
  [ "$status" -eq 0 ]
}

@test "Contents/Info.plist declares CFBundleExecutable matching the launcher binary" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  run /usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$APP/Contents/Info.plist"
  [ "$status" -eq 0 ]
  [ "$output" = "ntfsmac-gui" ]
}

@test "GUI Info.plist is the single product version source for helper and CLI diagnostics" {
  # shellcheck source=../../cli/lib/version.sh
  source "$REPO_ROOT/cli/lib/version.sh"
  ntfsmac_load_product_version "$REPO_ROOT"
  run /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$REPO_ROOT/gui/Info.plist"
  [ "$status" -eq 0 ]
  [ "$output" = "$NTFSMAC_VERSION" ]
  run /usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$REPO_ROOT/gui/Info.plist"
  [ "$output" = "$NTFSMAC_BUILD_VERSION" ]
  run /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$REPO_ROOT/helper/Info.plist"
  [ "$output" = "$NTFSMAC_VERSION" ]
  run /usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$REPO_ROOT/helper/Info.plist"
  [ "$output" = "$NTFSMAC_BUILD_VERSION" ]
  run /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$REPO_ROOT/helper/Info-Modern.plist"
  [ "$output" = "$NTFSMAC_VERSION" ]
  run /usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$REPO_ROOT/helper/Info-Modern.plist"
  [ "$output" = "$NTFSMAC_BUILD_VERSION" ]
}

@test "package-app hard-stops before build when canonical version metadata drifts" {
  local mismatched_info="$OUT_DIR/mismatched-Info.plist"
  cp "$REPO_ROOT/gui/Info.plist" "$mismatched_info"
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString 999" "$mismatched_info"
  NTFSMAC_PRODUCT_INFO_PLIST_OVERRIDE="$mismatched_info" run "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not match app version"* ]]
}

@test "ad-hoc signs the helper binary, the gui binary, and the outer bundle" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]

  run codesign -dv "$APP/Contents/Resources/ntfsmac-helper"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Signature=adhoc"* ]]

  run codesign -dv "$APP/Contents/MacOS/ntfsmac-gui"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Signature=adhoc"* ]]

  run codesign -dv "$APP"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Signature=adhoc"* ]]
}

@test "Package.swift embeds variant-specific helper metadata while preserving Legacy sections" {
  # The Mach-O __info_plist/__launchd_plist sections are added at `swift build` link time
  # (Package.swift's linkerSettings on the ntfsmac-helper target), not by this script — this
  # script only copies+signs the already-linked binary. A fixture binary standing in for the
  # real swift-build output has no such sections, so verify the linker wiring statically
  # instead of otool-ing a fixture that was never actually linked with these flags.
  run grep -c -- '__info_plist' "$REPO_ROOT/Package.swift"
  [ "$status" -eq 0 ]
  run grep -c -- '__launchd_plist' "$REPO_ROOT/Package.swift"
  [ "$status" -eq 0 ]
  run grep -F 'Info-Modern.plist' "$REPO_ROOT/Package.swift"
  [ "$status" -eq 0 ]
  run grep -F 'launchd-modern.plist' "$REPO_ROOT/Package.swift"
  [ "$status" -eq 0 ]
}

@test "rejects an unknown helper variant before touching output" {
  NTFSMAC_HELPER_VARIANT=experimental run "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"must be 'modern' or 'legacy'"* ]]
}

@test "defaults to ad-hoc signing and accepts an explicit release identity" {
  run grep -F 'SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"' "$SCRIPT"
  [ "$status" -eq 0 ]
  run grep -F -- '--options runtime' "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "fails clearly when the swift release binaries are missing" {
  rm -f "$RELEASE_DIR/ntfsmac-gui"
  run "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"HARD-STOP"* ]]
}
