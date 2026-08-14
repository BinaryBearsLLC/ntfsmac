#!/bin/bash
# build/make-dmg.sh — wraps build/package-app.sh's dist/ntfsmac.app into an ad-hoc DMG
# (L4: GUI ships DMG-only, never a Homebrew cask — no notarization, no paid Developer ID).
#
# The writable staging image is configured through Finder, then converted to the final
# compressed image. Nothing here re-signs the .app (that already happened in
# package-app.sh); Gatekeeper's ad-hoc-signature warning on first open is expected and
# documented (right-click → Open), per PLAN.md R3.
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
DMG_OUT="${NTFSMAC_DMG_OUT:-$REPO_ROOT/dist/ntfsmac.dmg}"
VOLUME_NAME="${NTFSMAC_DMG_VOLUME_NAME:-ntfsmac Installer}"
BACKGROUND_RENDERER="$SCRIPT_DIR/render-dmg-background.swift"
FINDER_LAYOUT="$SCRIPT_DIR/configure-dmg.applescript"

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
  if [[ ! -f "$BACKGROUND_RENDERER" || ! -f "$FINDER_LAYOUT" ]]; then
    echo "make-dmg: HARD-STOP — professional DMG layout assets are missing" >&2
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

  if ! cp -R "$APP" "$payload/"; then
    echo "make-dmg: HARD-STOP — failed to stage $APP" >&2
    exit 1
  fi
  if ! ln -s /Applications "$payload/Applications"; then
    echo "make-dmg: HARD-STOP — failed to create Applications symlink" >&2
    exit 1
  fi
  if ! xcrun swift "$BACKGROUND_RENDERER" \
    "$payload/.background/ntfsmac-dmg-background.png"; then
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

  if ! osascript "$FINDER_LAYOUT" "$mount_dir"; then
    echo "make-dmg: HARD-STOP — Finder layout configuration failed" >&2
    exit 1
  fi
  if [[ ! -f "$mount_dir/.DS_Store" ]]; then
    echo "make-dmg: HARD-STOP — Finder did not persist the professional layout" >&2
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

  echo "make-dmg: done — $DMG_OUT"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
