#!/usr/bin/env bats
# tests/build/lock.bats — p0-sources-lock acceptance checks (PLAN.md §6).

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  LOCK_SH="$REPO_ROOT/build/lib/lock.sh"
  LOCK_FILE="$REPO_ROOT/build/sources.lock"
}

@test "sources.lock exists" {
  [ -f "$LOCK_FILE" ]
}

@test "every required pin key is present" {
  for key in ANYLINUXFS_VERSION ANYLINUXFS_COMMIT VMPROXY_VERSION \
             GO_TOOLCHAIN_VERSION \
             RUST_TOOLCHAIN_VERSION RUST_TOOLCHAIN_ACTION_COMMIT \
             ACTIONS_CHECKOUT_COMMIT ACTIONS_SETUP_GO_COMMIT \
             ACTIONS_CONFIGURE_PAGES_COMMIT ACTIONS_UPLOAD_PAGES_ARTIFACT_COMMIT \
             ACTIONS_DEPLOY_PAGES_COMMIT \
             CARGO_ANYHOW_VERSION CARGO_CROSSBEAM_EPOCH_VERSION \
             CARGO_PLIST_VERSION CARGO_QUICK_XML_VERSION \
             CARGO_LRU_VERSION \
             CARGO_ANYLINUXFS_LOCK_SHA256 \
             CARGO_COMMON_UTILS_LOCK_SHA256 CARGO_VMPROXY_LOCK_SHA256 \
             CARGO_VMRUNNER_SYS_LOCK_SHA256 \
             LIBKRUN_BRANCH LIBKRUN_VERSION LIBKRUN_CRATE_SHA256 \
             LIBKRUNFW_VERSION LIBKRUNFW_IMAGES_SHA256 LIBKRUNFW_MODULES_SHA256 \
             VMNET_HELPER_VERSION VMNET_HELPER_COMMIT VMNET_HELPER_SHA256 \
             GVPROXY_VERSION GVPROXY_COMMIT GVPROXY_X_CRYPTO_VERSION GVPROXY_GO_OVERLAY_SHA256 \
             ALPINE_TAG ALPINE_DIGEST ALPINE_BASE_PACKAGES_SHA256 ALPINE_PACKAGES_SHA256 ALPINE_APKS_SHA256 \
             UTIL_LINUX_BREW_FORMULA; do
    run "$LOCK_SH" get "$key"
    [ "$status" -eq 0 ]
    [ -n "$output" ]
  done
}

@test "init-freebsd key is absent" {
  run grep -i "init-freebsd\|INIT_FREEBSD" "$LOCK_FILE"
  [ "$status" -ne 0 ]
}

@test "no key holds the literal :latest" {
  run bash -c "grep -v '^#' '$LOCK_FILE' | grep -i ':latest'"
  [ "$status" -ne 0 ]
}

@test "lock.sh get returns non-zero for unknown key" {
  run "$LOCK_SH" get NOT_A_REAL_KEY
  [ "$status" -ne 0 ]
}

@test "alpine tag is a specific patch version, not a floating tag" {
  run "$LOCK_SH" get ALPINE_TAG
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

@test "libkrun registry version and checksum match both upstream Cargo locks" {
  local expected_version expected_checksum cargo_lock block
  expected_version="$($LOCK_SH get LIBKRUN_VERSION)"
  expected_checksum="$($LOCK_SH get LIBKRUN_CRATE_SHA256)"
  [[ "$expected_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
  [[ "$expected_checksum" =~ ^[0-9a-f]{64}$ ]]

  for cargo_lock in \
    "$REPO_ROOT/vendor/src/anylinuxfs/anylinuxfs/Cargo.lock" \
    "$REPO_ROOT/vendor/src/anylinuxfs/vmrunner-sys/Cargo.lock"; do
    block="$(awk 'BEGIN { RS = "" } /name = "libkrun"/ { print; exit }' "$cargo_lock")"
    [[ "$block" == *"version = \"$expected_version\""* ]]
    [[ "$block" == *'source = "registry+https://github.com/rust-lang/crates.io-index"'* ]]
    [[ "$block" == *"checksum = \"$expected_checksum\""* ]]
  done
}
