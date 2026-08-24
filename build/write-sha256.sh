#!/bin/bash
# Write and immediately verify a portable SHA-256 sidecar for one release artifact.
set -euo pipefail

if [[ "$#" -ne 1 ]]; then
  echo "usage: $0 <artifact>" >&2
  exit 2
fi

ARTIFACT="$1"
[[ -f "$ARTIFACT" ]] || {
  echo "write-sha256: artifact missing: $ARTIFACT" >&2
  exit 1
}

ARTIFACT_DIR="$(cd -- "$(dirname -- "$ARTIFACT")" &>/dev/null && pwd)"
ARTIFACT_NAME="$(basename -- "$ARTIFACT")"
SIDECAR="$ARTIFACT_DIR/${ARTIFACT_NAME}.sha256"
TEMP_SIDECAR="${SIDECAR}.tmp.$$"

cleanup() {
  rm -f -- "$TEMP_SIDECAR"
}
trap cleanup EXIT

(
  cd "$ARTIFACT_DIR"
  shasum -a 256 "$ARTIFACT_NAME"
) > "$TEMP_SIDECAR"

(
  cd "$ARTIFACT_DIR"
  shasum -a 256 -c "$(basename -- "$TEMP_SIDECAR")" >/dev/null
)

mv -f -- "$TEMP_SIDECAR" "$SIDECAR"
trap - EXIT
printf 'write-sha256: OK — %s\n' "$SIDECAR"
