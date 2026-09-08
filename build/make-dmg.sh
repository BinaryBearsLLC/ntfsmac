#!/bin/bash
# build/make-dmg.sh — wraps build/package-app.sh's dist/ntfsmac.app into a DMG.
#
# The writable staging image is configured through Finder, then converted to the final
# compressed image. Nothing here re-signs the .app (that already happened in
# package-app.sh). Official builds additionally sign the final disk image with the same
# BinaryBears Developer ID identity before notarization.
#
# hdiutil writes its output to a space-free, off-volume temp path, then a plain `cp` lands
# the finished .dmg in dist/. Real bug, reproduced: writing UDZO output straight to dist/
# (this repo's own volume — a network-mounted NTFS share, "Windows Shared Folder")
# produced a DMG Finder reports as "disk image is corrupted" on mount. hdiutil's
# compressed-format finalization does block-level writes/fsyncs this volume doesn't handle
# correctly — same class of issue build/init-rootfs.sh already documents for the OCI
# blob-copy step ("inappropriate ioctl for device"). Plain sequential writes/copies are
# confirmed fine on this volume; only that finalization pattern isn't.
set -uo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." &>/dev/null && pwd)"

APP="${NTFSMAC_APP_BUNDLE:-$REPO_ROOT/dist/ntfsmac.app}"
# shellcheck source=build/lib/release-version.sh
source "$SCRIPT_DIR/lib/release-version.sh"
PRODUCT_VERSION="$(release_version "$REPO_ROOT/gui/Info.plist")" || exit 1
DMG_OUT="${NTFSMAC_DMG_OUT:-$REPO_ROOT/dist/ntfsmac-${PRODUCT_VERSION}-Apple-Silicon.dmg}"
VOLUME_NAME="${NTFSMAC_DMG_VOLUME_NAME:-ntfsmac Installer}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
SIGNING_KEYCHAIN="${SIGNING_KEYCHAIN:-}"
BACKGROUND_RENDERER="$SCRIPT_DIR/render-dmg-background.swift"
BRAND_BACKGROUND="${NTFSMAC_DMG_BACKGROUND:-$SCRIPT_DIR/dmg-assets/binarybears-background.png}"
BRAND_ARROW="${NTFSMAC_DMG_ARROW:-$SCRIPT_DIR/dmg-assets/install-arrow.jpeg}"
LAYOUT_CONFIG="${NTFSMAC_DMG_LAYOUT:-$SCRIPT_DIR/dmg-assets/layout.json}"
WEBSITE_LINK="$SCRIPT_DIR/dmg-assets/binarybears.com.webloc"
WEBSITE_ICON="${NTFSMAC_DMG_WEBSITE_ICON:-$SCRIPT_DIR/dmg-assets/binarybears-link-icon.png}"
FILE_ICON_SETTER="$SCRIPT_DIR/set-file-icon.swift"
FINDER_LAYOUT="$SCRIPT_DIR/configure-dmg.applescript"

layout_value() {
  /usr/bin/plutil -extract "$1" raw "$LAYOUT_CONFIG" 2>/dev/null
}

cleanup() {
  if [[ "${dmg_attached:-0}" -eq 1 && -n "${mount_dir:-}" ]]; then
    hdiutil detach "$mount_dir" -quiet >/dev/null 2>&1 \
      || hdiutil detach "$mount_dir" -force -quiet >/dev/null 2>&1 \
      || true
  fi
  [[ -z "${stage:-}" ]] || rm -rf "$stage"
}

main() {
  if [[ ! -d "$APP" ]]; then
    echo "make-dmg: HARD-STOP — app bundle not found: $APP (run build/package-app.sh first)" >&2
    exit 1
  fi
  if [[ ! -f "$BACKGROUND_RENDERER" || ! -f "$BRAND_BACKGROUND" || \
    ! -f "$BRAND_ARROW" || ! -f "$LAYOUT_CONFIG" || \
    ! -f "$WEBSITE_LINK" || ! -f "$WEBSITE_ICON" || ! -f "$FILE_ICON_SETTER" || \
    ! -f "$FINDER_LAYOUT" ]]; then
    echo "make-dmg: HARD-STOP — professional DMG layout assets are missing" >&2
    exit 1
  fi
  if [[ "$(/usr/bin/shasum -a 256 "$BRAND_BACKGROUND" | /usr/bin/awk '{print $1}')" != \
    "40bf0ec23be2fb92ce31fc50c70f9e05c966471c3e4c43529b5ccf7f00f6b338" ]]; then
    echo "make-dmg: HARD-STOP — unapproved BinaryBears DMG background: $BRAND_BACKGROUND" >&2
    exit 1
  fi
  if [[ "$(/usr/bin/shasum -a 256 "$WEBSITE_ICON" | /usr/bin/awk '{print $1}')" != \
    "3ee9694dfac22cbebac7ce12c00a1cfc133eca886c32ac1d234729b73b26e584" ]]; then
    echo "make-dmg: HARD-STOP — unapproved BinaryBears website icon: $WEBSITE_ICON" >&2
    exit 1
  fi
  if [[ "$(/usr/bin/shasum -a 256 "$BRAND_ARROW" | /usr/bin/awk '{print $1}')" != \
    "f948bc1d80ad0c84bdc724d2693b4446c11b311dec5f43b54dd4053d8d099e5b" ]]; then
    echo "make-dmg: HARD-STOP — unapproved BinaryBears DMG arrow: $BRAND_ARROW" >&2
    exit 1
  fi
  if [[ "$(layout_value schemaVersion)" != "1" || \
    "$(layout_value canvas.width)" != "720" || "$(layout_value canvas.height)" != "460" ]]; then
    echo "make-dmg: HARD-STOP — invalid BinaryBears DMG layout configuration" >&2
    exit 1
  fi
  if [[ "$(/usr/bin/plutil -extract URL raw "$WEBSITE_LINK" 2>/dev/null)" != \
    "$(layout_value website.url)" ]]; then
    echo "make-dmg: HARD-STOP — invalid BinaryBears website link asset" >&2
    exit 1
  fi
  command -v hdiutil >/dev/null 2>&1 || {
    echo "make-dmg: HARD-STOP — hdiutil is unavailable" >&2
    exit 1
  }
  command -v osascript >/dev/null 2>&1 || {
    echo "make-dmg: HARD-STOP — osascript is unavailable" >&2
    exit 1
  }
  command -v xcrun >/dev/null 2>&1 || {
    echo "make-dmg: HARD-STOP — xcrun is unavailable" >&2
    exit 1
  }

  # Not `local`: the EXIT trap fires after main() returns (at actual process exit, not
  # function return) — a `local` would already be out of scope by then, making `$stage`
  # unbound under `set -u` and skipping cleanup entirely.
  stage="$(mktemp -d)"
  dmg_attached=0
  trap cleanup EXIT

  payload="$stage/payload"
  mkdir -p "$payload/.background"
  website_filename="$(layout_value website.filename)"
  website_visible_size="$(layout_value website.visibleIconSize)"
  finder_icon_size="$(layout_value finder.iconSize)"
  finder_text_size="$(layout_value finder.textSize)"
  app_x="$(layout_value finder.items.application.0)"
  app_y="$(layout_value finder.items.application.1)"
  applications_x="$(layout_value finder.items.applicationsFolder.0)"
  applications_y="$(layout_value finder.items.applicationsFolder.1)"
  website_x="$(layout_value finder.items.website.0)"
  website_y="$(layout_value finder.items.website.1)"
  if [[ -z "$website_filename" || "$(layout_value website.labelVisible)" != "false" ]]; then
    echo "make-dmg: HARD-STOP — website link must use the approved invisible Finder label" >&2
    exit 1
  fi

  # Both distributions install the same visible product name. The Legacy distinction belongs to
  # the DMG filename, volume label, Settings metadata, and helper lifecycle — never to a P2 label
  # or a second application name in /Applications.
  if ! cp -R "$APP" "$payload/ntfsmac.app"; then
    echo "make-dmg: HARD-STOP — failed to stage $APP" >&2
    exit 1
  fi
  if ! ln -s /Applications "$payload/Applications"; then
    echo "make-dmg: HARD-STOP — failed to create Applications symlink" >&2
    exit 1
  fi
  if ! cp "$WEBSITE_LINK" "$payload/$website_filename"; then
    echo "make-dmg: HARD-STOP — failed to stage the BinaryBears website link" >&2
    exit 1
  fi
  if ! xcrun SetFile -a E "$payload/$website_filename"; then
    echo "make-dmg: HARD-STOP — failed to hide the website link extension" >&2
    exit 1
  fi
  if ! xcrun swift "$FILE_ICON_SETTER" \
    "$payload/$website_filename" "$WEBSITE_ICON" "$website_visible_size" "$finder_icon_size"; then
    echo "make-dmg: HARD-STOP — failed to apply the BinaryBears website icon" >&2
    exit 1
  fi
  if ! xcrun swift "$BACKGROUND_RENDERER" \
    "$payload/.background/ntfsmac-dmg-background.png" "$BRAND_BACKGROUND" \
    "$BRAND_ARROW" "$LAYOUT_CONFIG"; then
    echo "make-dmg: HARD-STOP — failed to render the DMG background" >&2
    exit 1
  fi

  rw_dmg="$stage/ntfsmac-layout.dmg"
  tmp_dmg="$stage/ntfsmac-final.dmg"
  mount_dir="$stage/mount"
  mkdir -p "$mount_dir"

  if ! hdiutil create -volname "$VOLUME_NAME" -srcfolder "$payload" -ov \
    -format UDRW -fs HFS+ "$rw_dmg" 2>&1; then
    echo "make-dmg: HARD-STOP — writable image creation failed" >&2
    exit 1
  fi

  if ! hdiutil attach "$rw_dmg" -mountpoint "$mount_dir" -readwrite \
    -noverify -noautoopen -nobrowse >/dev/null; then
    echo "make-dmg: HARD-STOP — writable image attach failed" >&2
    exit 1
  fi
  dmg_attached=1

  if ! osascript "$FINDER_LAYOUT" "$mount_dir" "$website_filename" \
    "$app_x" "$app_y" "$applications_x" "$applications_y" \
    "$website_x" "$website_y" "$finder_icon_size" "$finder_text_size"; then
    echo "make-dmg: HARD-STOP — Finder layout configuration failed" >&2
    exit 1
  fi
  if [[ ! -f "$mount_dir/.DS_Store" ]]; then
    echo "make-dmg: HARD-STOP — Finder did not persist the professional layout" >&2
    exit 1
  fi

  # Finder's layout update removes a pre-existing .VolumeIcon.icns while rebuilding the volume
  # metadata, so apply the approved icon only after that update has completed.
  if ! cp "$APP/Contents/Resources/AppIcon.icns" "$mount_dir/.VolumeIcon.icns"; then
    echo "make-dmg: HARD-STOP — failed to apply the ntfsmac DMG volume icon" >&2
    exit 1
  fi
  if ! xcrun SetFile -a C "$mount_dir"; then
    echo "make-dmg: HARD-STOP — failed to mark the DMG volume with its custom icon" >&2
    exit 1
  fi

  sync
  if ! hdiutil detach "$mount_dir" -quiet; then
    echo "make-dmg: HARD-STOP — writable image detach failed" >&2
    exit 1
  fi
  dmg_attached=0

  # Finalize off-volume, then copy sequentially to dist/. See the header note about the
  # repository volume's block-write behavior.
  if ! hdiutil convert "$rw_dmg" -ov -format UDZO -imagekey zlib-level=9 \
    -o "$tmp_dmg" >/dev/null; then
    echo "make-dmg: HARD-STOP — compressed image conversion failed" >&2
    exit 1
  fi
  if ! hdiutil verify "$tmp_dmg" >/dev/null; then
    echo "make-dmg: HARD-STOP — generated DMG verification failed" >&2
    exit 1
  fi

  mkdir -p "$(dirname "$DMG_OUT")"
  rm -f "$DMG_OUT"

  if ! cp "$tmp_dmg" "$DMG_OUT"; then
    echo "make-dmg: HARD-STOP — failed to copy built DMG to $DMG_OUT" >&2
    exit 1
  fi

  if [[ "$SIGNING_IDENTITY" != "-" ]]; then
    local -a sign_args=(-s "$SIGNING_IDENTITY" --force --timestamp)
    [[ -z "$SIGNING_KEYCHAIN" ]] || sign_args+=(--keychain "$SIGNING_KEYCHAIN")
    if ! codesign "${sign_args[@]}" "$DMG_OUT"; then
      echo "make-dmg: HARD-STOP — failed to sign $DMG_OUT" >&2
      exit 1
    fi
  fi

  echo "make-dmg: done — $DMG_OUT"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
