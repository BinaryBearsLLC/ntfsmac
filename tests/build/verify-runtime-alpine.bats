#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SCRIPT="$REPO_ROOT/build/verify-runtime-alpine.sh"
  BIN_DIR="$(mktemp -d)"
  # shellcheck source=../../build/lib/lock.sh
  source "$REPO_ROOT/build/lib/lock.sh"
  # shellcheck source=../../cli/lib/runtime-alpine.sh
  source "$REPO_ROOT/cli/lib/runtime-alpine.sh"
  runtime_alpine_load

  printf '#!/bin/bash\n# %s\n# %s\n# %s\n' \
    "$ALPINE_RUNTIME_REF" "$ALPINE_RUNTIME_BASE_DIR" "$ALPINE_RUNTIME_VERSION" > "$BIN_DIR/anylinuxfs"
  printf '#!/bin/bash\n# %s\n' "$ALPINE_RUNTIME_REF" > "$BIN_DIR/init-rootfs"
  chmod +x "$BIN_DIR/anylinuxfs" "$BIN_DIR/init-rootfs"
}

teardown() {
  rm -rf "$BIN_DIR"
}

@test "accepts only binaries containing the approved runtime contract" {
  NTFSMAC_VENDOR_BIN_DIR="$BIN_DIR" run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"approved Alpine"* ]]
}

@test "rejects a floating alpine latest fallback" {
  printf '# alpine:latest\n' >> "$BIN_DIR/init-rootfs"
  NTFSMAC_VENDOR_BIN_DIR="$BIN_DIR" run "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"forbidden floating runtime reference"* ]]
}

@test "rejects a binary missing the approved digest" {
  printf '#!/bin/bash\n' > "$BIN_DIR/init-rootfs"
  chmod +x "$BIN_DIR/init-rootfs"
  NTFSMAC_VENDOR_BIN_DIR="$BIN_DIR" run "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not contain the approved digest-only"* ]]
}

@test "rejects floating bytes anywhere in the staged shipping tree" {
  local shipped
  shipped="$(mktemp -d)"
  printf 'docker_ref = "alpine:latest"\n' > "$shipped/config.toml"
  NTFSMAC_VENDOR_BIN_DIR="$BIN_DIR" NTFSMAC_SHIPPED_TREE="$shipped" run "$SCRIPT"
  rm -rf "$shipped"
  [ "$status" -ne 0 ]
  [[ "$output" == *"staged shipped runtime"* ]]
}
