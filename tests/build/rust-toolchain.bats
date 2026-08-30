#!/usr/bin/env bats
# tests/build/rust-toolchain.bats — exact Rust build-toolchain acceptance checks.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  LOCK_SH="$REPO_ROOT/build/lib/lock.sh"
  RUST_HELPER="$REPO_ROOT/build/lib/rust-toolchain.sh"
}

@test "Rust toolchain pin is an exact patch release" {
  run "$LOCK_SH" get RUST_TOOLCHAIN_VERSION
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

@test "locked Rust toolchain is available and selected exactly" {
  local expected
  expected="$($LOCK_SH get RUST_TOOLCHAIN_VERSION)"
  run bash -c 'source "$1"; source "$2"; rust_with_locked_toolchain rustc --version' _ \
    "$LOCK_SH" "$RUST_HELPER"
  [ "$status" -eq 0 ]
  [[ "$output" == "rustc $expected "* ]]
}

@test "Rust build entrypoints activate the locked toolchain" {
  for script in "$REPO_ROOT/build/build-all.sh" "$REPO_ROOT/build/init-rootfs.sh"; do
    run grep -F 'source "$SCRIPT_DIR/lib/rust-toolchain.sh"' "$script"
    [ "$status" -eq 0 ]
    run grep -F "rust_activate_locked_toolchain" "$script"
    [ "$status" -eq 0 ]
  done
}

@test "CI and release workflows resolve Rust from sources.lock without stable compiler drift" {
  for workflow in "$REPO_ROOT/.github/workflows/ci.yml" "$REPO_ROOT/.github/workflows/release.yml"; do
    run grep -F "./build/lib/lock.sh get RUST_TOOLCHAIN_VERSION" "$workflow"
    [ "$status" -eq 0 ]
    run grep -E 'toolchain:[[:space:]]*stable' "$workflow"
    [ "$status" -ne 0 ]
  done
}

@test "helper rejects a malformed toolchain pin before invoking rustup" {
  local lock
  lock="$BATS_TEST_TMPDIR/sources.lock"
  printf 'RUST_TOOLCHAIN_VERSION=stable\n' > "$lock"
  NTFSMAC_SOURCES_LOCK="$lock" run bash -c \
    'source "$1"; source "$2"; rust_with_locked_toolchain rustc --version' _ \
    "$LOCK_SH" "$RUST_HELPER"
  [ "$status" -ne 0 ]
  [[ "$output" == *"HARD-STOP"* ]]
}
