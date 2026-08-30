#!/bin/bash
# build/lib/go-toolchain.sh — run Go commands with the exact sources.lock toolchain.
#
# The caller must source build/lib/lock.sh first. GOTOOLCHAIN=<exact-version> lets an older local
# Go launcher obtain the selected official toolchain without changing the host-global install.
# Go authenticates downloaded toolchain modules through the checksum database and fails closed
# when that verification is unavailable.

go_locked_toolchain_version() {
  local version
  version="$(lock_get GO_TOOLCHAIN_VERSION)" || return 1
  if [[ ! "$version" =~ ^go[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "go-toolchain: HARD-STOP — invalid GO_TOOLCHAIN_VERSION pin: $version" >&2
    return 1
  fi
  printf '%s\n' "$version"
}

go_with_locked_toolchain() {
  local version
  version="$(go_locked_toolchain_version)" || return 1
  if ! command -v go >/dev/null 2>&1; then
    echo "go-toolchain: HARD-STOP — Go launcher not found on PATH" >&2
    return 1
  fi
  GOTOOLCHAIN="$version" go "$@"
}
