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
  WEBSITE_FILENAME="$(plutil -extract website.filename raw "$REPO_ROOT/build/dmg-assets/layout.json")"
  [ -f "$MOUNT_DIR/$WEBSITE_FILENAME" ]
  [ "$(plutil -extract URL raw "$MOUNT_DIR/$WEBSITE_FILENAME")" = \
    "https://binarybears.com/" ]
  run xattr -p com.apple.ResourceFork "$MOUNT_DIR/$WEBSITE_FILENAME"
  [ "$status" -eq 0 ]
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
  [[ "$output" != *"binarybears.com.webloc"* ]]

  hdiutil detach "$MOUNT_DIR" -quiet
  rm -rf "$MOUNT_DIR"
}

@test "professional layout sources are present and renderer emits the expected canvas" {
  [ -f "$REPO_ROOT/build/configure-dmg.applescript" ]
  [ -f "$REPO_ROOT/build/render-dmg-background.swift" ]
  [ -f "$REPO_ROOT/build/dmg-assets/binarybears-background.png" ]
  [ -f "$REPO_ROOT/build/dmg-assets/install-arrow.jpeg" ]
  [ -f "$REPO_ROOT/build/dmg-assets/layout.json" ]
  [ -f "$REPO_ROOT/build/dmg-assets/binarybears-link-icon.png" ]
  [ -f "$REPO_ROOT/build/set-file-icon.swift" ]

  run shasum -a 256 "$REPO_ROOT/build/dmg-assets/binarybears-background.png"
  [ "$status" -eq 0 ]
  [[ "$output" == \
    40bf0ec23be2fb92ce31fc50c70f9e05c966471c3e4c43529b5ccf7f00f6b338* ]]

  run shasum -a 256 "$REPO_ROOT/build/dmg-assets/binarybears-link-icon.png"
  [ "$status" -eq 0 ]
  [[ "$output" == \
    3ee9694dfac22cbebac7ce12c00a1cfc133eca886c32ac1d234729b73b26e584* ]]

  run shasum -a 256 "$REPO_ROOT/build/dmg-assets/install-arrow.jpeg"
  [ "$status" -eq 0 ]
  [[ "$output" == \
    f948bc1d80ad0c84bdc724d2693b4446c11b311dec5f43b54dd4053d8d099e5b* ]]

  run bash -c '! strings "$1" | grep -Eiq "c2pa|jumbf|/Users/"' _ \
    "$REPO_ROOT/build/dmg-assets/install-arrow.jpeg"
  [ "$status" -eq 0 ]

  [ "$(plutil -extract website.labelVisible raw "$REPO_ROOT/build/dmg-assets/layout.json")" = false ]
  [ "$(plutil -extract finder.items.website.0 raw "$REPO_ROOT/build/dmg-assets/layout.json")" = 635 ]
  [ "$(plutil -extract finder.items.website.1 raw "$REPO_ROOT/build/dmg-assets/layout.json")" = 338 ]

  BACKGROUND="$OUT_DIR/background.png"
  run xcrun swift "$REPO_ROOT/build/render-dmg-background.swift" "$BACKGROUND" \
    "$REPO_ROOT/build/dmg-assets/binarybears-background.png" \
    "$REPO_ROOT/build/dmg-assets/install-arrow.jpeg" \
    "$REPO_ROOT/build/dmg-assets/layout.json"
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
