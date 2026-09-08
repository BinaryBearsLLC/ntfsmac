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
