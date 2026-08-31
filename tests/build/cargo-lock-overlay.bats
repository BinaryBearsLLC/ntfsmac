#!/usr/bin/env bats
# tests/build/cargo-lock-overlay.bats — exact disposable Cargo graph acceptance checks.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  LOCK_SH="$REPO_ROOT/build/lib/lock.sh"
  RUST_HELPER="$REPO_ROOT/build/lib/rust-toolchain.sh"
  OVERLAY_HELPER="$REPO_ROOT/build/lib/cargo-lock-overlay.sh"
}

@test "Cargo overlay pins exact versions and complete lock hashes" {
  run "$LOCK_SH" get CARGO_ANYHOW_VERSION
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]

  for key in CARGO_ANYLINUXFS_LOCK_SHA256 CARGO_COMMON_UTILS_LOCK_SHA256 \
             CARGO_VMPROXY_LOCK_SHA256 CARGO_VMRUNNER_SYS_LOCK_SHA256; do
    run "$LOCK_SH" get "$key"
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^[0-9a-f]{64}$ ]]
  done
}

@test "overlay updates a disposable common-utils lock and leaves the submodule clean" {
  local fixture before_status after_status
  fixture="$BATS_TEST_TMPDIR/common-utils"
  cp -R "$REPO_ROOT/vendor/src/anylinuxfs/common-utils" "$fixture"
  before_status="$(git -C "$REPO_ROOT/vendor/src/anylinuxfs" status --porcelain)"

  run bash -c '
    source "$1"
    source "$2"
    source "$3"
    cargo_apply_lock_overlay "$4" CARGO_COMMON_UTILS_LOCK_SHA256
  ' _ "$LOCK_SH" "$RUST_HELPER" "$OVERLAY_HELPER" "$fixture"
  [ "$status" -eq 0 ]
  [[ "$output" == *"common-utils lock verified"* ]]
  run bash -c 'source "$1"; cargo_lock_package_versions "$2" anyhow' _ \
    "$OVERLAY_HELPER" "$fixture/Cargo.lock"
  [ "$status" -eq 0 ]
  [ "$output" = "1.0.104" ]

  after_status="$(git -C "$REPO_ROOT/vendor/src/anylinuxfs" status --porcelain)"
  [ "$after_status" = "$before_status" ]
}

@test "overlay hard-stops when a complete lock hash drifts" {
  local fixture lock_fixture
  fixture="$BATS_TEST_TMPDIR/common-utils"
  lock_fixture="$BATS_TEST_TMPDIR/sources.lock"
  cp -R "$REPO_ROOT/vendor/src/anylinuxfs/common-utils" "$fixture"
  sed 's/^CARGO_COMMON_UTILS_LOCK_SHA256=.*/CARGO_COMMON_UTILS_LOCK_SHA256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/' \
    "$REPO_ROOT/build/sources.lock" > "$lock_fixture"

  NTFSMAC_SOURCES_LOCK="$lock_fixture" run bash -c '
    source "$1"
    source "$2"
    source "$3"
    cargo_apply_lock_overlay "$4" CARGO_COMMON_UTILS_LOCK_SHA256
  ' _ "$LOCK_SH" "$RUST_HELPER" "$OVERLAY_HELPER" "$fixture"
  [ "$status" -ne 0 ]
  [[ "$output" == *"HARD-STOP"*"Cargo.lock hash mismatch"* ]]
}
