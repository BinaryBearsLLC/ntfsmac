#!/usr/bin/env bats
# tests/build/make-dmg.bats — build/make-dmg.sh acceptance checks.
#
# Wraps an already-assembled .app bundle (build/package-app.sh's output) into an
# DMG-only distributable. Fixture builds omit the optional Developer ID signature.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SCRIPT="$REPO_ROOT/build/make-dmg.sh"

  APP_PARENT="$(mktemp -d)"
  OUT_DIR="$(mktemp -d)"
  APP="$APP_PARENT/ntfsmac.app"

  # A minimal but real .app shape — make-dmg.sh only cares that it's a directory
  # named *.app with something inside, not that it's fully signed (that's
  # package-app.sh's job, covered separately in package-app.bats).
  mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
  cp /bin/echo "$APP/Contents/MacOS/ntfsmac-gui"
  cp "$REPO_ROOT/gui/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

  export NTFSMAC_APP_BUNDLE="$APP"
  export NTFSMAC_DMG_OUT="$OUT_DIR/ntfsmac.dmg"
}

teardown() {
  rm -rf "$APP_PARENT" "$OUT_DIR"
}

@test "make-dmg.sh exists and is executable" {
  [ -x "$SCRIPT" ]
}

@test "creates a dmg containing the app bundle and an Applications symlink" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -f "$NTFSMAC_DMG_OUT" ]

  MOUNT_DIR="$(mktemp -d)"
  run hdiutil attach "$NTFSMAC_DMG_OUT" -mountpoint "$MOUNT_DIR" -nobrowse -readonly -noautoopen
  [ "$status" -eq 0 ]

  [ -d "$MOUNT_DIR/ntfsmac.app" ]
  [ -L "$MOUNT_DIR/Applications" ]
  [ "$(readlink "$MOUNT_DIR/Applications")" = "/Applications" ]
  [ -f "$MOUNT_DIR/.DS_Store" ]
  [ -f "$MOUNT_DIR/.background/ntfsmac-dmg-background.png" ]
  [ -f "$MOUNT_DIR/.VolumeIcon.icns" ]

  run sips -g pixelWidth -g pixelHeight \
    "$MOUNT_DIR/.background/ntfsmac-dmg-background.png"
  [ "$status" -eq 0 ]
  [[ "$output" == *"pixelWidth: 720"* ]]
  [[ "$output" == *"pixelHeight: 460"* ]]

  run strings "$MOUNT_DIR/.DS_Store"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ntfsmac-dmg-background.png"* ]]

  hdiutil detach "$MOUNT_DIR" -quiet
  rm -rf "$MOUNT_DIR"
}

@test "professional layout sources are present and renderer emits the expected canvas" {
  [ -f "$REPO_ROOT/build/configure-dmg.applescript" ]
  [ -f "$REPO_ROOT/build/render-dmg-background.swift" ]

  BACKGROUND="$OUT_DIR/background.png"
  run xcrun swift "$REPO_ROOT/build/render-dmg-background.swift" "$BACKGROUND"
  [ "$status" -eq 0 ]
  [ -f "$BACKGROUND" ]

  run sips -g pixelWidth -g pixelHeight "$BACKGROUND"
  [ "$status" -eq 0 ]
  [[ "$output" == *"pixelWidth: 720"* ]]
  [[ "$output" == *"pixelHeight: 460"* ]]
}

@test "a Legacy source bundle is still presented as ntfsmac.app inside the DMG" {
  local legacy_app="$APP_PARENT/ntfsmac-legacy.app"
  mv "$APP" "$legacy_app"
  export NTFSMAC_APP_BUNDLE="$legacy_app"

  run "$SCRIPT"
  [ "$status" -eq 0 ]

  MOUNT_DIR="$(mktemp -d)"
  run hdiutil attach "$NTFSMAC_DMG_OUT" -mountpoint "$MOUNT_DIR" -nobrowse -readonly -noautoopen
  [ "$status" -eq 0 ]
  [ -d "$MOUNT_DIR/ntfsmac.app" ]
  [ ! -e "$MOUNT_DIR/ntfsmac-legacy.app" ]
  hdiutil detach "$MOUNT_DIR" -quiet
  rm -rf "$MOUNT_DIR"
}

@test "fails clearly when the app bundle is missing" {
  rm -rf "$APP"
  run "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"HARD-STOP"* ]]
}
