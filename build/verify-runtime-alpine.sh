#!/bin/bash
# Release gate for the runtime image actually embedded in shipped anylinuxfs/init-rootfs binaries.
set -uo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." &>/dev/null && pwd)"
# shellcheck source=lib/lock.sh
source "$SCRIPT_DIR/lib/lock.sh"
# shellcheck source=../cli/lib/runtime-alpine.sh
source "$REPO_ROOT/cli/lib/runtime-alpine.sh"

BIN_DIR="${NTFSMAC_VENDOR_BIN_DIR:-$REPO_ROOT/vendor/bin}"
SHIPPED_TREE="${NTFSMAC_SHIPPED_TREE:-}"

fail() { echo "verify-runtime-alpine: FAIL — $1" >&2; }

binary_contains() {
  strings "$1" | grep -F -- "$2" >/dev/null 2>&1
}

main() {
  runtime_alpine_load || exit 1

  local failed=0 bin
  for bin in anylinuxfs init-rootfs; do
    if [[ ! -x "$BIN_DIR/$bin" ]]; then
      fail "$BIN_DIR/$bin missing or not executable"
      failed=1
      continue
    fi
    if binary_contains "$BIN_DIR/$bin" 'alpine:latest'; then
      fail "$bin contains the forbidden floating runtime reference alpine:latest"
      failed=1
    fi
    if ! binary_contains "$BIN_DIR/$bin" "$ALPINE_RUNTIME_REF"; then
      fail "$bin does not contain the approved digest-only reference $ALPINE_RUNTIME_REF"
      failed=1
    fi
  done

  if [[ -x "$BIN_DIR/anylinuxfs" ]]; then
    if ! binary_contains "$BIN_DIR/anylinuxfs" "$ALPINE_RUNTIME_BASE_DIR"; then
      fail "anylinuxfs does not contain the versioned runtime cache directory"
      failed=1
    fi
    if ! binary_contains "$BIN_DIR/anylinuxfs" "$ALPINE_RUNTIME_VERSION"; then
      fail "anylinuxfs does not contain the expected rootfs version marker"
      failed=1
    fi
  fi

  if [[ -n "$SHIPPED_TREE" ]]; then
    if [[ ! -d "$SHIPPED_TREE" ]]; then
      fail "shipped tree does not exist: $SHIPPED_TREE"
      failed=1
    elif LC_ALL=C grep -R -a -F 'alpine:latest' "$SHIPPED_TREE" >/dev/null 2>&1; then
      fail "the staged shipped runtime contains forbidden alpine:latest bytes"
      failed=1
    fi
  fi

  [[ "$failed" -eq 0 ]] || exit 1
  echo "verify-runtime-alpine: approved Alpine $ALPINE_RUNTIME_TAG runtime $ALPINE_RUNTIME_REF"
  echo "verify-runtime-alpine: versioned cache $ALPINE_RUNTIME_BASE_DIR"
}

main "$@"
