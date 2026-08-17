#!/bin/bash
# Produce deterministic app/helper derivatives from the two approved brand masters.
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/.." &>/dev/null && pwd)
APP_MASTER="$REPO_ROOT/brand/ntfsmac-icon.png"
HELPER_MASTER="$REPO_ROOT/brand/ntfsmac-helper-icon.png"
APP_SOURCE="$REPO_ROOT/gui/Resources/AppIcon-source.png"
APP_ICNS="$REPO_ROOT/gui/Resources/AppIcon.icns"
HELPER_SOURCE="$REPO_ROOT/gui/Resources/HelperIcon.png"

EXPECTED_APP_SHA256="fcfddbb98d4745fa1e34fd7778283d348a613fa8f5be0a7f500b38cf05eeddc3"
EXPECTED_HELPER_SHA256="b7ec1c8c06656c92f8303a45db792346cdb7ee9e2936ff1f5634a049d85e04f9"

sha256() {
  /usr/bin/shasum -a 256 "$1" | /usr/bin/awk '{print $1}'
}

require_hash() {
  local path="$1" expected="$2" actual
  [[ -f "$path" ]] || { echo "sync-brand-assets: missing $path" >&2; exit 1; }
  actual="$(sha256 "$path")"
  [[ "$actual" == "$expected" ]] || {
    echo "sync-brand-assets: unapproved master $path ($actual)" >&2
    exit 1
  }
}

require_hash "$APP_MASTER" "$EXPECTED_APP_SHA256"
require_hash "$HELPER_MASTER" "$EXPECTED_HELPER_SHA256"
command -v sips >/dev/null || { echo "sync-brand-assets: sips unavailable" >&2; exit 1; }
command -v iconutil >/dev/null || { echo "sync-brand-assets: iconutil unavailable" >&2; exit 1; }

iconset_dir="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$iconset_dir"
trap 'rm -rf "${iconset_dir%/AppIcon.iconset}"' EXIT

sips -z 1024 1024 "$APP_MASTER" --out "$APP_SOURCE" >/dev/null
sips -z 512 512 "$HELPER_MASTER" --out "$HELPER_SOURCE" >/dev/null

while read -r size filename; do
  sips -z "$size" "$size" "$APP_SOURCE" --out "$iconset_dir/$filename" >/dev/null
done <<'SIZES'
16 icon_16x16.png
32 icon_16x16@2x.png
32 icon_32x32.png
64 icon_32x32@2x.png
128 icon_128x128.png
256 icon_128x128@2x.png
256 icon_256x256.png
512 icon_256x256@2x.png
512 icon_512x512.png
1024 icon_512x512@2x.png
SIZES

iconutil -c icns "$iconset_dir" -o "$APP_ICNS"
echo "sync-brand-assets: approved app and helper assets synchronized"
