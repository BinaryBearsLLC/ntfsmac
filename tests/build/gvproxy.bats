#!/usr/bin/env bats
# tests/build/gvproxy.bats — v-gvproxy acceptance (PLAN.md §6).
# Runs the real build (network clone + go build) — same live-verification pattern as
# fetch-prebuilt.sh. Slow; not mocked, since the acceptance criterion is a real arm64 binary.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SCRIPT="$REPO_ROOT/build/build-gvproxy.sh"
  BIN="$REPO_ROOT/vendor/bin/gvproxy"
}

@test "build-gvproxy.sh exists and is executable" {
  [ -x "$SCRIPT" ]
}

@test "build-gvproxy.sh HARD-STOPs on an unresolved TODO-UNRESOLVED pin" {
  local lock
  lock="$(mktemp)"
  printf 'GVPROXY_VERSION=TODO-UNRESOLVED\nGVPROXY_COMMIT=TODO-UNRESOLVED\n' > "$lock"
  NTFSMAC_SOURCES_LOCK="$lock" run "$SCRIPT"
  rm -f "$lock"
  [ "$status" -ne 0 ]
  [[ "$output" == *"HARD-STOP"* ]]
}

@test "gvproxy security overlay pins an exact x/crypto version and module graph hash" {
  local version overlay_sha256
  version="$($REPO_ROOT/build/lib/lock.sh get GVPROXY_X_CRYPTO_VERSION)"
  overlay_sha256="$($REPO_ROOT/build/lib/lock.sh get GVPROXY_GO_OVERLAY_SHA256)"
  [[ "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]
  [[ "$overlay_sha256" =~ ^[0-9a-f]{64}$ ]]
}

@test "build-gvproxy.sh HARD-STOPs if the generated module overlay hash drifts" {
  local lock
  lock="$BATS_TEST_TMPDIR/sources.lock"
  sed 's/^GVPROXY_GO_OVERLAY_SHA256=.*/GVPROXY_GO_OVERLAY_SHA256=0000000000000000000000000000000000000000000000000000000000000000/' \
    "$REPO_ROOT/build/sources.lock" > "$lock"
  NTFSMAC_SOURCES_LOCK="$lock" run "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Go overlay hash mismatch"* ]]
}

@test "builds gvproxy from source: vendor/bin/gvproxy is an executable arm64 binary" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -x "$BIN" ]
  run file "$BIN"
  [[ "$output" == *"arm64"* ]]
  run "$BIN" --version
  [ "$status" -eq 0 ]
  [ "$output" = "gvproxy version v0.8.9" ]
  run go version -m "$BIN"
  [ "$status" -eq 0 ]
  [[ "$output" == *$'dep\tgolang.org/x/crypto\tv0.55.0'* ]]
  run git -C "$REPO_ROOT/build/.cache/gvisor-tap-vsock" status --porcelain --untracked-files=no
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
