#!/usr/bin/env bats
# tests/build/rootfs.bats — v-alpine-rootfs acceptance (PLAN.md §6).
#
# Runs the real build (network pull of alpine at the locked tag+digest, real cargo/go
# build of a patched init-rootfs) — same live-verification pattern as fetch-prebuilt.bats
# and gvproxy.bats. Checks the generated vm-setup.sh (the package manifest for this rootfs
# — see build/init-rootfs.sh's header for why full VM-boot package installation isn't
# reachable yet: it needs vendor/bin/vmproxy, a v-anylinuxfs-build artifact) against
# the exact full add-on closure. The smaller trimmed list remains the reviewed direct
# feature set; exact transitive versions come from build/alpine-packages.lock.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SCRIPT="$REPO_ROOT/build/init-rootfs.sh"
  # shellcheck source=../../build/lib/lock.sh
  source "$REPO_ROOT/build/lib/lock.sh"
  # shellcheck source=../../cli/lib/runtime-alpine.sh
  source "$REPO_ROOT/cli/lib/runtime-alpine.sh"
  runtime_alpine_load
}

@test "init-rootfs.sh exists and is executable" {
  [ -x "$SCRIPT" ]
}

@test "compile-only rootfs mode builds without claiming VM acceptance" {
  NTFSMAC_ROOTFS_BUILD_MODE=compile-only run bash -c '
    source build/init-rootfs.sh
    rust_activate_locked_toolchain() { :; }
    runtime_alpine_load() {
      ALPINE_RUNTIME_TAG=fixture; ALPINE_RUNTIME_DIGEST=fixture
      ALPINE_BASE_PACKAGES_SHA256=fixture; ALPINE_PACKAGES_SHA256=fixture
    }
    verify_package_lock() { :; }
    verify_apk_lock() { :; }
    verify_alpine_digest() { :; }
    prepare_build_copy() { :; }
    verify_apk_artifacts() { :; }
    build_vmrunner_sys() { echo built-rust; }
    build_init_rootfs_bin() { echo built-go; }
    vendor_init_rootfs_bin() { echo signed-binary; }
    run_init_rootfs() { echo unexpected-vm-boot; return 1; }
    main
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *built-rust* && "$output" == *built-go* && "$output" == *signed-binary* ]]
  [[ "$output" == *"acceptance NOT RUN"* ]]
  [[ "$output" != *unexpected-vm-boot* ]]
}

@test "unknown rootfs build mode fails closed" {
  NTFSMAC_ROOTFS_BUILD_MODE=skip-all run "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown rootfs build mode"* ]]
}

@test "init-rootfs.sh HARD-STOPs on an unresolved TODO-UNRESOLVED pin" {
  local lock
  lock="$(mktemp)"
  sed 's/^ALPINE_TAG=.*/ALPINE_TAG=TODO-UNRESOLVED/' "$REPO_ROOT/build/sources.lock" > "$lock"
  NTFSMAC_SOURCES_LOCK="$lock" run "$SCRIPT"
  rm -f "$lock"
  [ "$status" -ne 0 ]
  [[ "$output" == *"HARD-STOP"* ]]
}

@test "generated vm-setup.sh package manifest matches the exact add-on lock" {
  if [[ "${NTFSMAC_ROOTFS_BUILD_MODE:-full}" == compile-only ]]; then
    skip "Native Hypervisor/package-install acceptance runs separately on a physical Mac"
  fi
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  local rootfs_home
  rootfs_home="$(echo "$output" | sed -n 's/^init-rootfs: NTFSMAC_ROOTFS_HOME=//p' | tail -1)"
  [ -n "$rootfs_home" ]

  local setup_script
  setup_script="$rootfs_home/.anylinuxfs/$ALPINE_RUNTIME_BASE_DIR/rootfs/usr/local/bin/vm-setup.sh"
  [ -n "$setup_script" ]
  [ -f "$setup_script" ]

  run grep '^# ntfsmac locked package set: ' "$setup_script"
  [ "$status" -eq 0 ]
  local package_args actual expected
  package_args="${output#*: }"
  actual="$(tr ' ' '\n' <<< "$package_args" | LC_ALL=C sort)"
  expected="$(cat "$REPO_ROOT/build/alpine-packages.lock")"
  [ "$actual" = "$expected" ]

  actual="$(awk '/^done <<.*NTFSMAC_APK_LOCK/ { capture=1; next } capture && /^NTFSMAC_APK_LOCK$/ { exit } capture { print }' "$setup_script")"
  expected="$(cat "$REPO_ROOT/build/alpine-apks.lock")"
  [ "$actual" = "$expected" ]

  run grep -F 'apk --no-network --no-cache add "$APK_DIR"/*.apk' "$setup_script"
  [ "$status" -eq 0 ]
  run grep -F 'apk --update' "$setup_script"
  [ "$status" -ne 0 ]
  run grep -E '%!\((MISSING|EXTRA)' "$setup_script"
  [ "$status" -ne 0 ]

  run grep -F "echo \"$(sed -n 's/^ALPINE_PACKAGES_SHA256=//p' "$REPO_ROOT/build/sources.lock")\" > /etc/ntfsmac-alpine-packages.sha256" "$setup_script"
  [ "$status" -eq 0 ]
  run grep -F "echo \"$(sed -n 's/^ALPINE_APKS_SHA256=//p' "$REPO_ROOT/build/sources.lock")\" > /etc/ntfsmac-alpine-apks.sha256" "$setup_script"
  [ "$status" -eq 0 ]
}

@test "patched init-rootfs rejects custom packages that bypass the lock" {
  local cache_dir
  cache_dir="$(mktemp -d)"
  NTFSMAC_ROOTFS_CACHE_DIR="$cache_dir" run bash -c '
    source build/init-rootfs.sh
    runtime_alpine_load
    prepare_build_copy
    grep -F "ntfsmac package lock does not allow custom Alpine packages" "$CACHE_DIR/init-rootfs/main.go"
  '
  rm -rf "$cache_dir"
  [ "$status" -eq 0 ]
}

@test "rootfs package verification rejects an unexpected extra package" {
  local rootfs lock cache
  rootfs="$BATS_TEST_TMPDIR/rootfs-extra"
  lock="$BATS_TEST_TMPDIR/expected-packages.lock"
  cache="$BATS_TEST_TMPDIR/package-verifier-cache"
  mkdir -p "$rootfs/lib/apk/db" "$cache"
  printf 'P:bash\nV:5.3.3-r1\n\nP:unexpected\nV:1.0-r0\n' > "$rootfs/lib/apk/db/installed"
  printf 'bash=5.3.3-r1\n' > "$lock"

  NTFSMAC_ROOTFS_CACHE_DIR="$cache" run bash -c '
    source build/init-rootfs.sh
    verify_rootfs_package_versions "$1" test "$2"
  ' _ "$rootfs" "$lock"

  [ "$status" -ne 0 ]
  [[ "$output" == *"package manifest is not exact"* ]]
  [[ "$output" == *"unexpected=1.0-r0"* ]]
}

@test "vendors the built init-rootfs binary to vendor/bin/init-rootfs" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -x "$REPO_ROOT/vendor/bin/init-rootfs" ]
  run file "$REPO_ROOT/vendor/bin/init-rootfs"
  [[ "$output" == *"arm64"* ]]
}

@test "vendor/bin/init-rootfs carries the hypervisor entitlement (build/sign.sh actually ran)" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  run codesign -d --entitlements - --xml "$REPO_ROOT/vendor/bin/init-rootfs"
  [[ "$output" == *"com.apple.security.hypervisor"* ]]
}
