#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SCRIPT="$REPO_ROOT/build/write-sha256.sh"
  FIXTURE_DIR="$(mktemp -d)"
}

teardown() {
  rm -rf "$FIXTURE_DIR"
}

@test "checksum writer creates a portable sidecar and verifies it" {
  printf 'ntfsmac checksum fixture\n' > "$FIXTURE_DIR/release artifact.dmg"

  run "$SCRIPT" "$FIXTURE_DIR/release artifact.dmg"
  [ "$status" -eq 0 ]
  [ -f "$FIXTURE_DIR/release artifact.dmg.sha256" ]
  run grep -F 'release artifact.dmg' "$FIXTURE_DIR/release artifact.dmg.sha256"
  [ "$status" -eq 0 ]
  [[ "$output" != *"$FIXTURE_DIR"* ]]

  run bash -c 'cd "$1" && shasum -a 256 -c "release artifact.dmg.sha256"' _ "$FIXTURE_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *'release artifact.dmg: OK'* ]]
}

@test "checksum writer refuses a missing artifact without leaving a sidecar" {
  run "$SCRIPT" "$FIXTURE_DIR/missing.dmg"
  [ "$status" -ne 0 ]
  [[ "$output" == *"artifact missing"* ]]
  [ ! -e "$FIXTURE_DIR/missing.dmg.sha256" ]
}
