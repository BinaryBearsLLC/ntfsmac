#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  TEST_HOME="$(mktemp -d)"
  LOCK_FIXTURE="$(mktemp)"
  cp "$REPO_ROOT/build/sources.lock" "$LOCK_FIXTURE"
  export NTFSMAC_SOURCES_LOCK="$LOCK_FIXTURE"
  # shellcheck source=../../build/lib/lock.sh
  source "$REPO_ROOT/build/lib/lock.sh"
  # shellcheck source=../../cli/lib/runtime-alpine.sh
  source "$REPO_ROOT/cli/lib/runtime-alpine.sh"
  runtime_alpine_load
}

teardown() {
  rm -rf "$TEST_HOME"
  rm -f "$LOCK_FIXTURE"
}

make_initialized_cache() {
  local base
  base="$(runtime_alpine_cache_path "$TEST_HOME")"
  mkdir -p "$base/rootfs/bin" "$base/rootfs/usr/bin" "$base/rootfs/usr/sbin" "$base/rootfs/usr/local/bin" "$base/rootfs/etc"
  printf '%s' "$ALPINE_RUNTIME_VERSION" > "$base/rootfs.ver"
  : > "$base/rootfs/bin/bash"
  : > "$base/rootfs/usr/bin/ntfs-3g.probe"
  : > "$base/rootfs/usr/bin/ntfsinfo"
  : > "$base/rootfs/usr/sbin/rpc.nfsd"
  : > "$base/rootfs/usr/local/bin/entrypoint.sh"
  : > "$base/rootfs/vmproxy"
  printf 'rpc_pipefs\nnfsd\n' > "$base/rootfs/etc/fstab"
  printf '%s' "$ALPINE_BASE_PACKAGES_SHA256" > "$base/rootfs/etc/ntfsmac-alpine-base-packages.sha256"
  printf '%s' "$ALPINE_PACKAGES_SHA256" > "$base/rootfs/etc/ntfsmac-alpine-packages.sha256"
  printf '%s' "$ALPINE_APKS_SHA256" > "$base/rootfs/etc/ntfsmac-alpine-apks.sha256"
}

@test "derives one digest-only pull reference plus tag-aware cache and marker from sources.lock" {
  [[ "$ALPINE_RUNTIME_REF" == "docker.io/library/alpine@sha256:"* ]]
  [[ "$ALPINE_RUNTIME_BASE_DIR" == "alpine-${ALPINE_RUNTIME_TAG}-"* ]]
  [[ "$ALPINE_RUNTIME_BASE_DIR" == *"-${ALPINE_PACKAGES_SHA256:0:12}-${ALPINE_APKS_SHA256:0:12}-${OFFLINE_RUNTIME_SHA256:0:12}-r5" ]]
  [[ "$ALPINE_RUNTIME_VERSION" == "ntfsmac-alpine-v5|"* ]]
  [[ "$ALPINE_RUNTIME_VERSION" == *"digest=${ALPINE_RUNTIME_DIGEST}"* ]]
  [[ "$ALPINE_RUNTIME_VERSION" == *"anylinuxfs="* ]]
  [[ "$ALPINE_RUNTIME_VERSION" == *"base_packages=${ALPINE_BASE_PACKAGES_SHA256}"* ]]
  [[ "$ALPINE_RUNTIME_VERSION" == *"packages=${ALPINE_PACKAGES_SHA256}"* ]]
  [[ "$ALPINE_RUNTIME_VERSION" == *"apks=${ALPINE_APKS_SHA256}"* ]]
  [[ "$ALPINE_RUNTIME_REF" != *"latest"* ]]
  [[ "$ALPINE_RUNTIME_REF" != *":${ALPINE_RUNTIME_TAG}@"* ]]
}

@test "v5 offline contract never reuses the prior v4 cache" {
  local current_base previous_base
  current_base="$(runtime_alpine_cache_path "$TEST_HOME")"
  previous_base="${current_base%-${OFFLINE_RUNTIME_SHA256:0:12}-r5}-r4"
  mkdir -p "$previous_base/rootfs"
  printf 'ntfsmac-alpine-v4' > "$previous_base/rootfs.ver"

  run runtime_alpine_prepare_cache "$TEST_HOME"

  [ "$status" -eq 0 ]
  [[ "$output" == *"first run"* ]]
  [ -d "$previous_base/rootfs" ]
  [ ! -e "$current_base" ]
}

@test "v5 cache is incomplete without the read-only dirty-flag inspector" {
  make_initialized_cache
  rm "$(runtime_alpine_cache_path "$TEST_HOME")/rootfs/usr/bin/ntfsinfo"

  run runtime_alpine_cache_state "$TEST_HOME"

  [ "$status" -eq 0 ]
  [ "$output" = "incomplete" ]
}

@test "v5 cache is incomplete without the exact package-lock marker" {
  make_initialized_cache
  rm "$(runtime_alpine_cache_path "$TEST_HOME")/rootfs/etc/ntfsmac-alpine-packages.sha256"

  run runtime_alpine_cache_state "$TEST_HOME"

  [ "$status" -eq 0 ]
  [ "$output" = "incomplete" ]
}

@test "v5 cache is incomplete without the exact APK artifact marker" {
  make_initialized_cache
  rm "$(runtime_alpine_cache_path "$TEST_HOME")/rootfs/etc/ntfsmac-alpine-apks.sha256"

  run runtime_alpine_cache_state "$TEST_HOME"

  [ "$status" -eq 0 ]
  [ "$output" = "incomplete" ]
}

@test "clean initialization is reported without touching disk or starting a download" {
  run runtime_alpine_cache_state "$TEST_HOME"
  [ "$status" -eq 0 ]
  [ "$output" = "not_initialized" ]
  [ ! -e "$TEST_HOME/.anylinuxfs" ]
}

@test "a complete matching cache is reusable offline" {
  make_initialized_cache
  local failing_tools
  failing_tools="$(mktemp -d)"
  printf '#!/bin/bash\nexit 99\n' > "$failing_tools/curl"
  chmod +x "$failing_tools/curl"

  PATH="$failing_tools:$PATH" run runtime_alpine_prepare_cache "$TEST_HOME"
  rm -rf "$failing_tools"
  [ "$status" -eq 0 ]
  [[ "$output" == *"reusing pinned Alpine"* ]]
  [ "$(runtime_alpine_cache_state "$TEST_HOME")" = "initialized" ]
}

@test "legacy cache is retained side-by-side for migration and rollback" {
  mkdir -p "$TEST_HOME/.anylinuxfs/alpine/rootfs"
  run runtime_alpine_prepare_cache "$TEST_HOME"
  [ "$status" -eq 0 ]
  [[ "$output" == *"legacy Alpine cache detected and preserved"* ]]
  [ -d "$TEST_HOME/.anylinuxfs/alpine/rootfs" ]
  [ ! -e "$(runtime_alpine_cache_path "$TEST_HOME")" ]
}

@test "digest or version mismatch is preserved before a fresh initialization" {
  local base
  base="$(runtime_alpine_cache_path "$TEST_HOME")"
  mkdir -p "$base/rootfs"
  printf 'wrong-digest-marker' > "$base/rootfs.ver"

  run runtime_alpine_prepare_cache "$TEST_HOME"
  [ "$status" -eq 0 ]
  [[ "$output" == *"preserved the incompatible"* ]]
  [ ! -e "$base" ]
  compgen -G "${base}.preserved-*" >/dev/null
}

@test "an interrupted initialization is preserved and safely retryable" {
  local base
  base="$(runtime_alpine_cache_path "$TEST_HOME")"
  mkdir -p "$base/oci/blobs"
  printf 'partial' > "$base/oci/blobs/download"

  run runtime_alpine_prepare_cache "$TEST_HOME"
  [ "$status" -eq 0 ]
  [[ "$output" == *"interrupted runs can be retried"* ]]
  [ ! -e "$base" ]
  compgen -G "${base}.preserved-*" >/dev/null
}

@test "upgrade and rollback caches remain independent" {
  make_initialized_cache
  local previous_base
  previous_base="$(runtime_alpine_cache_path "$TEST_HOME")"

  sed -i '' \
    's/^ALPINE_TAG=.*/ALPINE_TAG=3.24.2/; s/^ALPINE_DIGEST=.*/ALPINE_DIGEST=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/' \
    "$LOCK_FIXTURE"
  runtime_alpine_load
  local upgraded_base
  upgraded_base="$(runtime_alpine_cache_path "$TEST_HOME")"

  [ "$previous_base" != "$upgraded_base" ]
  [ -d "$previous_base" ]
  run runtime_alpine_prepare_cache "$TEST_HOME"
  [ "$status" -eq 0 ]
  [[ "$output" == *"first run"* ]]
  [ -d "$previous_base" ]
  [ ! -e "$upgraded_base" ]
}

@test "invalid digest metadata fails closed" {
  sed -i '' 's/^ALPINE_DIGEST=.*/ALPINE_DIGEST=sha256:not-a-digest/' "$LOCK_FIXTURE"
  run runtime_alpine_load
  [ "$status" -ne 0 ]
  [[ "$output" == *"64 lowercase hexadecimal"* ]]
}

@test "invalid package lock metadata fails closed" {
  sed -i '' 's/^ALPINE_PACKAGES_SHA256=.*/ALPINE_PACKAGES_SHA256=not-a-digest/' "$LOCK_FIXTURE"
  run runtime_alpine_load
  [ "$status" -ne 0 ]
  [[ "$output" == *"runtime lock hashes"* ]]
}

@test "invalid APK artifact lock metadata fails closed" {
  sed -i '' 's/^ALPINE_APKS_SHA256=.*/ALPINE_APKS_SHA256=not-a-digest/' "$LOCK_FIXTURE"
  run runtime_alpine_load
  [ "$status" -ne 0 ]
  [[ "$output" == *"runtime lock hashes"* ]]
}

@test "offline payload identity invalidates cache without deleting previous runtime" {
  make_initialized_cache
  local old_base old_version
  old_base="$(runtime_alpine_cache_path "$TEST_HOME")"
  old_version="$ALPINE_RUNTIME_VERSION"
  sed -i '' 's/^OFFLINE_RUNTIME_SHA256=.*/OFFLINE_RUNTIME_SHA256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/' "$LOCK_FIXTURE"
  runtime_alpine_load
  [ "$(runtime_alpine_cache_path "$TEST_HOME")" != "$old_base" ]
  [ "$ALPINE_RUNTIME_VERSION" != "$old_version" ]
  [ "$(runtime_alpine_cache_state "$TEST_HOME")" = "not_initialized" ]
  [ -f "$old_base/rootfs.ver" ]
}
