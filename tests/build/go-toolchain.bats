#!/usr/bin/env bats
# tests/build/go-toolchain.bats — exact Go build-toolchain acceptance checks.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  LOCK_SH="$REPO_ROOT/build/lib/lock.sh"
  GO_HELPER="$REPO_ROOT/build/lib/go-toolchain.sh"
}

@test "Go toolchain pin is an exact patch release" {
  run "$LOCK_SH" get GO_TOOLCHAIN_VERSION
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^go[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

@test "locked Go toolchain is available and selected exactly" {
  local expected
  expected="$($LOCK_SH get GO_TOOLCHAIN_VERSION)"
  run bash -c 'source "$1"; source "$2"; go_with_locked_toolchain version' _ \
    "$LOCK_SH" "$GO_HELPER"
  [ "$status" -eq 0 ]
  [[ "$output" == "go version $expected "* ]]
}

@test "Go build entrypoints use the locked-toolchain wrapper" {
  run grep -F "go_with_locked_toolchain build" "$REPO_ROOT/build/init-rootfs.sh"
  [ "$status" -eq 0 ]
  run grep -F "go_with_locked_toolchain build" "$REPO_ROOT/build/build-gvproxy.sh"
  [ "$status" -eq 0 ]
  run bash -c \
    'grep -hEv "^[[:space:]]*#" "$@" | grep -E "(^|[[:space:]])go build([[:space:]]|$)"' _ \
    "$REPO_ROOT/build/init-rootfs.sh" "$REPO_ROOT/build/build-gvproxy.sh"
  [ "$status" -ne 0 ]
}

@test "CI and release workflows resolve Go from sources.lock without stable drift" {
  for workflow in "$REPO_ROOT/.github/workflows/ci.yml" "$REPO_ROOT/.github/workflows/release.yml"; do
    run grep -F "./build/lib/lock.sh get GO_TOOLCHAIN_VERSION" "$workflow"
    [ "$status" -eq 0 ]
    run grep -E 'go-version:[[:space:]]*["'\"']?stable' "$workflow"
    [ "$status" -ne 0 ]
  done
}

@test "helper rejects a malformed toolchain pin before invoking Go" {
  local lock
  lock="$BATS_TEST_TMPDIR/sources.lock"
  printf 'GO_TOOLCHAIN_VERSION=stable\n' > "$lock"
  NTFSMAC_SOURCES_LOCK="$lock" run bash -c \
    'source "$1"; source "$2"; go_with_locked_toolchain version' _ "$LOCK_SH" "$GO_HELPER"
  [ "$status" -ne 0 ]
  [[ "$output" == *"HARD-STOP"* ]]
}
