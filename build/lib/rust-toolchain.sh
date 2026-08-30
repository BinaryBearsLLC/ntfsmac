#!/bin/bash
# build/lib/rust-toolchain.sh — run Rust commands with the exact sources.lock toolchain.
#
# The caller must source build/lib/lock.sh first. rustup owns installation and target management;
# this helper only validates the immutable version and selects it without changing the user's
# default toolchain.

rust_locked_toolchain_version() {
  local version
  version="$(lock_get RUST_TOOLCHAIN_VERSION)" || return 1
  if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "rust-toolchain: HARD-STOP — invalid RUST_TOOLCHAIN_VERSION pin: $version" >&2
    return 1
  fi
  printf '%s\n' "$version"
}

rust_with_locked_toolchain() {
  local version
  version="$(rust_locked_toolchain_version)" || return 1
  if ! command -v rustup >/dev/null 2>&1; then
    echo "rust-toolchain: HARD-STOP — rustup not found on PATH" >&2
    return 1
  fi
  rustup run "$version" "$@"
}

rust_activate_locked_toolchain() {
  local version
  version="$(rust_locked_toolchain_version)" || return 1
  if ! command -v rustup >/dev/null 2>&1; then
    echo "rust-toolchain: HARD-STOP — rustup not found on PATH" >&2
    return 1
  fi
  if ! rustup run "$version" rustc --version >/dev/null 2>&1; then
    echo "rust-toolchain: HARD-STOP — Rust $version is not installed through rustup" >&2
    return 1
  fi
  export RUSTUP_TOOLCHAIN="$version"
}
