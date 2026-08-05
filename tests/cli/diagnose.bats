#!/usr/bin/env bats
# tests/cli/diagnose.bats — 2-diagnose acceptance (PLAN.md §6).
# Covers healthy + each degraded branch and the --json shape. diagnose is read-only —
# no privileged op is ever exercised or mocked here.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SCRIPT="$REPO_ROOT/cli/commands/diagnose.sh"
  FIXTURE_DIR="$(mktemp -d)"

  for name in anylinuxfs gvproxy vmnet-helper vmproxy; do
    printf '#!/bin/bash\nexit 0\n' > "$FIXTURE_DIR/$name"
    chmod +x "$FIXTURE_DIR/$name"
  done
  export NTFSMAC_ANYLINUXFS_BIN="$FIXTURE_DIR/anylinuxfs"
  export NTFSMAC_GVPROXY_BIN="$FIXTURE_DIR/gvproxy"
  export NTFSMAC_VMNET_HELPER_BIN="$FIXTURE_DIR/vmnet-helper"
  export NTFSMAC_VMPROXY_BIN="$FIXTURE_DIR/vmproxy"
  export NTFSMAC_HELPER_PATH_OVERRIDE="$FIXTURE_DIR/ntfsmac-helper"
  cp "$FIXTURE_DIR/anylinuxfs" "$NTFSMAC_HELPER_PATH_OVERRIDE"
  export NTFSMAC_MACOS_VERSION_OVERRIDE="14.5"
  export NTFSMAC_ARCHITECTURE_OVERRIDE="arm64"
  export NTFSMAC_DEFAULT_INTERFACE_OVERRIDE="en0"
  export NTFSMAC_NFS_MOUNT_COUNT_OVERRIDE="0"

  # Kernel pin fixture: a lock file + a modules.squashfs whose sha256 matches it.
  mkdir -p "$FIXTURE_DIR/kernel"
  printf 'fake modules content' > "$FIXTURE_DIR/kernel/modules.squashfs"
  local sha
  sha="$(shasum -a 256 "$FIXTURE_DIR/kernel/modules.squashfs" | awk '{print $1}')"
  printf 'LIBKRUNFW_MODULES_SHA256=%s\n' "$sha" > "$FIXTURE_DIR/sources.lock"
  printf 'ALPINE_TAG=3.23.5\n' >> "$FIXTURE_DIR/sources.lock"
  printf 'ALPINE_DIGEST=sha256:d858bb5442632a31bd4bca6c5e601dbe6b536fd7942092ea6a08a0a95805693c\n' >> "$FIXTURE_DIR/sources.lock"
  printf 'ANYLINUXFS_COMMIT=8aa9ccd6504e64ca26ce769c1623ed1741c6b7d3\n' >> "$FIXTURE_DIR/sources.lock"
  export NTFSMAC_SOURCES_LOCK="$FIXTURE_DIR/sources.lock"
  export NTFSMAC_VENDOR_KERNEL_DIR="$FIXTURE_DIR/kernel"
  export NTFSMAC_RUNTIME_HOME_OVERRIDE="$FIXTURE_DIR/runtime-home"
}

teardown() {
  rm -rf "$FIXTURE_DIR"
}

@test "healthy: all binaries present, kernel pin matches, no quarantine" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ntfsmac version: 1.0 (1)"* ]]
  [[ "$output" == *"architecture: arm64"* ]]
  [[ "$output" == *"privileged helper: installed"* ]]
  [[ "$output" == *"kernel pin: match"* ]]
  [[ "$output" == *"VPN default route: not detected"* ]]
  [[ "$output" == *"current NFS mount count: 0"* ]]
  [[ "$output" == *"overall: healthy"* ]]
}

@test "degraded: missing binary" {
  rm "$FIXTURE_DIR/vmproxy"
  run "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"missing components: vmproxy"* ]]
  [[ "$output" == *"overall: degraded"* ]]
}

@test "degraded: quarantined binary" {
  xattr -w com.apple.quarantine "0083;00000000;Safari;" "$FIXTURE_DIR/anylinuxfs"
  run "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"quarantined binaries: 1"* ]]
}

@test "degraded: kernel pin mismatch" {
  printf 'LIBKRUNFW_MODULES_SHA256=0000000000000000000000000000000000000000000000000000000000000000\n' > "$FIXTURE_DIR/sources.lock"
  run "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"kernel pin: mismatch"* ]]
}

@test "--json emits well-formed JSON with the expected fields" {
  run "$SCRIPT" --json
  [ "$status" -eq 0 ]
  [[ "$output" == \{*\} ]]
  [[ "$output" == *'"diagnostic_schema":3'* ]]
  [[ "$output" == *'"healthy":true'* ]]
  [[ "$output" == *'"ntfsmac_version":"1.0"'* ]]
  [[ "$output" == *'"build_version":"1"'* ]]
  [[ "$output" == *'"macos_version":"14.5"'* ]]
  [[ "$output" == *'"architecture":"arm64"'* ]]
  [[ "$output" == *'"helper_installed":true'* ]]
  [[ "$output" == *'"kernel_pin":"match"'* ]]
  [[ "$output" == *'"alpine_runtime_tag":"3.23.5"'* ]]
  [[ "$output" == *'"alpine_runtime_digest":"sha256:d858bb5442632a31bd4bca6c5e601dbe6b536fd7942092ea6a08a0a95805693c"'* ]]
  [[ "$output" == *'"alpine_runtime_state":"not_initialized"'* ]]
  [[ "$output" == *'"missing_binaries":0'* ]]
  [[ "$output" == *'"missing_components":[]'* ]]
  [[ "$output" == *'"quarantined_binaries":0'* ]]
  [[ "$output" == *'"quarantined_components":[]'* ]]
  [[ "$output" == *'"vpn_default_route":false'* ]]
  [[ "$output" == *'"nfs_mount_count":0'* ]]
}

@test "a legacy Alpine cache is reported without exposing its path" {
  mkdir -p "$NTFSMAC_RUNTIME_HOME_OVERRIDE/.anylinuxfs/alpine/rootfs"
  run "$SCRIPT" --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"alpine_runtime_state":"migration_available"'* ]]
  [[ "$output" != *"$NTFSMAC_RUNTIME_HOME_OVERRIDE"* ]]
}

@test "a mismatched pinned cache degrades health without exposing marker contents" {
  # shellcheck source=../../build/lib/lock.sh
  source "$REPO_ROOT/build/lib/lock.sh"
  # shellcheck source=../../cli/lib/runtime-alpine.sh
  source "$REPO_ROOT/cli/lib/runtime-alpine.sh"
  runtime_alpine_load
  local base
  base="$(runtime_alpine_cache_path "$NTFSMAC_RUNTIME_HOME_OVERRIDE")"
  mkdir -p "$base/rootfs"
  printf 'private-unapproved-marker' > "$base/rootfs.ver"

  run "$SCRIPT" --json
  [ "$status" -ne 0 ]
  [[ "$output" == *'"alpine_runtime_state":"mismatch"'* ]]
  [[ "$output" == *'"healthy":false'* ]]
  [[ "$output" != *"private-unapproved-marker"* ]]
  [[ "$output" != *"$base"* ]]
}

@test "--json names failing components without exposing local paths or network identity" {
  rm "$FIXTURE_DIR/vmproxy"
  xattr -w com.apple.quarantine "0083;00000000;Safari;" "$FIXTURE_DIR/gvproxy"
  export NTFSMAC_DEFAULT_INTERFACE_OVERRIDE="utun7"
  export NTFSMAC_NFS_MOUNT_COUNT_OVERRIDE="2"

  run "$SCRIPT" --json
  [ "$status" -ne 0 ]
  [[ "$output" == *'"missing_components":["vmproxy"]'* ]]
  [[ "$output" == *'"quarantined_components":["gvproxy"]'* ]]
  [[ "$output" == *'"vpn_default_route":true'* ]]
  [[ "$output" == *'"nfs_mount_count":2'* ]]
  [[ "$output" != *"$FIXTURE_DIR"* ]]
  [[ "$output" != *'"vpn_interface"'* ]]
  [[ "$output" != *'"ip_address"'* ]]
  [[ "$output" != *'"mount_paths"'* ]]
  [[ "$output" != *'"volume_labels"'* ]]
  [[ "$output" != *'"username"'* ]]
  [[ "$output" != *'"serial"'* ]]
}

@test "reports a supported macOS version and stays healthy" {
  export NTFSMAC_MACOS_VERSION_OVERRIDE="14.5"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"macOS version: 14.5"* ]]
  [[ "$output" == *"overall: healthy"* ]]
}

@test "--json includes the macos_version field" {
  export NTFSMAC_MACOS_VERSION_OVERRIDE="14.5"
  run "$SCRIPT" --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"macos_version":"14.5"'* ]]
}

@test "product version is resolved from project metadata rather than shell constants" {
  local product_info="$FIXTURE_DIR/Info.plist"
  cp "$REPO_ROOT/gui/Info.plist" "$product_info"
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString 9.8" "$product_info"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion 765" "$product_info"
  export NTFSMAC_PRODUCT_INFO_PLIST_OVERRIDE="$product_info"

  run "$SCRIPT" --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"ntfsmac_version":"9.8"'* ]]
  [[ "$output" == *'"build_version":"765"'* ]]
}

@test "degraded: non-arm64 architecture is unsupported" {
  export NTFSMAC_ARCHITECTURE_OVERRIDE="x86_64"
  run "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"architecture: x86_64"* ]]
  [[ "$output" == *"requires Apple Silicon"* ]]
}

@test "helper absence is reported but remains valid for a CLI-only install" {
  export NTFSMAC_HELPER_PATH_OVERRIDE=""
  run "$SCRIPT" --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"helper_installed":false'* ]]
  [[ "$output" == *'"healthy":true'* ]]
}

@test "helper presence does not depend on the unprivileged caller's execute permission" {
  chmod 400 "$NTFSMAC_HELPER_PATH_OVERRIDE"
  run "$SCRIPT" --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"helper_installed":true'* ]]
}

@test "degraded: macOS older than 13.0 is unsupported" {
  export NTFSMAC_MACOS_VERSION_OVERRIDE="12.6"
  run "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"macOS version: 12.6"* ]]
  [[ "$output" == *"unsupported"* ]]
  [[ "$output" == *"overall: degraded"* ]]
}

@test "an undetected macOS version is reported as unknown but not fatal" {
  # Explicit empty override simulates sw_vers returning nothing (the `-` default in
  # check_macos_version keeps an empty *set* value rather than re-running sw_vers).
  export NTFSMAC_MACOS_VERSION_OVERRIDE=""
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"macOS version: unknown"* ]]
  [[ "$output" == *"overall: healthy"* ]]
}

@test "falls back to \$PREFIX/libexec when a binary isn't on PATH (install.sh layout, not PATH by design)" {
  # Real install.sh layout: gvproxy/vmnet-helper/vmproxy live in libexec, never on PATH.
  # Without an env override or PATH entry, the old PATH-only check misreported these as
  # missing on every correctly-installed system.
  unset NTFSMAC_GVPROXY_BIN NTFSMAC_VMNET_HELPER_BIN NTFSMAC_VMPROXY_BIN
  local prefix_dir="$FIXTURE_DIR/prefix"
  mkdir -p "$prefix_dir/bin" "$prefix_dir/libexec"
  cp "$FIXTURE_DIR/anylinuxfs" "$prefix_dir/bin/anylinuxfs"
  cp "$FIXTURE_DIR/gvproxy" "$prefix_dir/libexec/gvproxy"
  cp "$FIXTURE_DIR/vmnet-helper" "$prefix_dir/libexec/vmnet-helper"
  cp "$FIXTURE_DIR/vmproxy" "$prefix_dir/libexec/vmproxy"
  export NTFSMAC_PREFIX="$prefix_dir"
  unset NTFSMAC_ANYLINUXFS_BIN
  export PATH="$prefix_dir/bin:/usr/bin:/bin"

  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"vendor binaries missing: 0"* ]]
}

@test "never performs a mount/unmount/pf/route operation (read-only)" {
  run grep -E '\bmount\(|anylinuxfs" (mount|unmount)|pfctl|route add|route delete' "$SCRIPT"
  [ "$status" -ne 0 ]
}
