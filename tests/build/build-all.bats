#!/usr/bin/env bats
# tests/build/build-all.bats — v-anylinuxfs-build acceptance (PLAN.md §6).
#
# Runs the real build (real cargo builds of anylinuxfs + vmproxy, real cargo test for all
# three crates, orchestrates fetch-prebuilt/build-gvproxy/init-rootfs) — same
# live-verification pattern as gvproxy.bats/rootfs.bats/fetch-prebuilt.bats. Slow (full
# release build from a clean cache dir); not mocked, since the acceptance criteria are a
# real arm64 anylinuxfs binary and real cargo test output.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SCRIPT="$REPO_ROOT/build/build-all.sh"
  BIN_ANYLINUXFS="$REPO_ROOT/vendor/bin/anylinuxfs"
  BIN_VMPROXY="$REPO_ROOT/vendor/bin/vmproxy"
}

@test "build-all.sh exists and is executable" {
  [ -x "$SCRIPT" ]
}

@test "build-all.sh does not build freebsd-bootstrap or vmproxy-bsd targets" {
  # Comments legitimately name these (explaining why they're cut) — assert no
  # actual build invocation targets them, not that the words never appear.
  run grep -E '(cargo|go) build.*(freebsd|vmproxy-bsd)|--target aarch64-unknown-freebsd|-Z build-std' "$SCRIPT"
  [ "$status" -ne 0 ]
}

@test "runtime source patch is idempotent across repeated clean preparations" {
  local cache_dir
  cache_dir="$(mktemp -d)"
  NTFSMAC_ANYLINUXFS_CACHE_DIR="$cache_dir" run bash -c '
    source build/build-all.sh
    prepare_build_copy
    prepare_build_copy
    test ! -d "$CACHE_DIR/etc/etc"
    test ! -d "$CACHE_DIR/share/share"
    test "$(grep -c "docker_ref = \\\"$ALPINE_RUNTIME_REF\\\"" "$CACHE_DIR/etc/anylinuxfs.toml")" -eq 1
  '
  rm -rf "$cache_dir"
  [ "$status" -eq 0 ]
}

@test "full build: anylinuxfs + vmproxy compile, cargo test passes for all three crates" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"cargo test — common-utils"* ]]
  [[ "$output" == *"cargo test — anylinuxfs"* ]]
  [[ "$output" == *"cargo test — vmproxy"* ]]
}

@test "vendor/bin/anylinuxfs exists and is an arm64 (host) executable" {
  [ -x "$BIN_ANYLINUXFS" ]
  run file "$BIN_ANYLINUXFS"
  [[ "$output" == *"arm64"* ]]
}

@test "vendor/bin/anylinuxfs carries the hypervisor entitlement (build/sign.sh actually ran)" {
  # Regression for a real bare-metal failure: a bare `codesign -s -` with no entitlements
  # passes `codesign -v` fine but can't boot the VM (Hypervisor.framework needs
  # com.apple.security.hypervisor) — "start vm error: Invalid argument (errno 22)".
  run codesign -d --entitlements - --xml "$BIN_ANYLINUXFS"
  [[ "$output" == *"com.apple.security.hypervisor"* ]]
}

@test "vendor/bin/vmproxy exists and is an aarch64 Linux (guest) executable" {
  [ -x "$BIN_VMPROXY" ]
  run file "$BIN_VMPROXY"
  [[ "$output" == *"ARM aarch64"* ]]
}

@test "vmproxy is embedded into the generated rootfs vm-setup.sh flow (no vmproxy-bsd artifact produced)" {
  [ ! -e "$REPO_ROOT/vendor/bin/vmproxy-bsd" ]
}

@test "build-all.sh wires static libblkid linking (no homebrew util-linux runtime dep)" {
  # Regression for tosbaha's crash (#1): anylinuxfs used to dynamically link
  # /opt/homebrew/*/libblkid.1.dylib (via libblkid-rs-sys + the submodule's
  # .cargo/config.toml PKG_CONFIG_PATH=/opt/homebrew/opt/util-linux/lib/pkgconfig),
  # so it aborted at launch on any machine without `brew install util-linux`.
  # The fix builds a static libblkid.a from a pinned util-linux source and tells
  # the anylinuxfs cargo build to link it statically. Assert the wiring is present:
  # PKG_CONFIG_ALL_STATIC=1 forces the pkg-config crate to static archives, and
  # PKG_CONFIG_PATH must point at our static-build output dir (not the homebrew
  # path) so the build picks up our .a + .pc, not the homebrew dylib. Cargo [env]
  # default force=false means a shell-exported PKG_CONFIG_PATH overrides the
  # submodule's hardcoded homebrew path — that override is what this checks.
  [ -f "$SCRIPT" ]
  run grep -E 'PKG_CONFIG_ALL_STATIC=1' "$SCRIPT"
  [ "$status" -eq 0 ]
  # Active (non-comment) PKG_CONFIG_PATH assignment only — comments legitimately name the
  # homebrew path to explain why we override it (same comment-tolerance the freebsd test
  # above uses). `^[[:space:]]*PKG_CONFIG_PATH=` matches the real assignment, not comment
  # lines that merely mention the variable.
  run grep -E '^[[:space:]]*PKG_CONFIG_PATH=' "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" != *"/opt/homebrew/opt/util-linux"* ]]
}

@test "vendor/bin/anylinuxfs does not dynamically link libblkid (static-linked, no DYLD abort)" {
  # The real acceptance guard for #1: even with the wiring above, the proof is
  # the built binary's own linkage. Any libblkid*.dylib entry here means the
  # static-link regressed and the tosbaha crash returns on machines without
  # `brew install util-linux`. Runs the real build (see full-build test above).
  [ -x "$BIN_ANYLINUXFS" ]
  run otool -L "$BIN_ANYLINUXFS"
  [ "$status" -eq 0 ]
  [[ "$output" != *"libblkid"* ]]
}
