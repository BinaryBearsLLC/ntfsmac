#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  PROBE="$REPO_ROOT/vendor/bin/anylinuxfs"
  PROBE_HOME="$BATS_TEST_TMPDIR/empty-home"
  mkdir -p "$PROBE_HOME"
}

@test "native filesystem probe fails without initializing a runtime or using the network" {
  run env HOME="$PROBE_HOME" sandbox-exec -p '(version 1)(allow default)(deny network*)' \
    "$PROBE" probe-filesystem disk99999s1
  [ "$status" -eq 1 ]
  [[ "$output" == *"filesystem metadata unavailable"* ]]
  [ -z "$(ls -A "$PROBE_HOME")" ]
}

@test "native filesystem probe rejects paths whole disks and injected identifiers" {
  for device in /dev/disk4s2 disk4 'disk4s2;id' $'disk4s2\n'; do
    run env HOME="$PROBE_HOME" "$PROBE" probe-filesystem "$device"
    [ "$status" -ne 0 ]
    [[ "$output" == *"rejected: expected diskNsM"* ]]
  done
  [ -z "$(ls -A "$PROBE_HOME")" ]
}

@test "packaging accepts the current native probe and rejects an older CLI" {
  run bash -c 'source "$1"; verify_filesystem_probe_cli "$2"' _ "$REPO_ROOT/build/package-app.sh" "$PROBE"
  [ "$status" -eq 0 ]
  local old_cli="$BATS_TEST_TMPDIR/old-cli"
  printf '#!/bin/sh\necho "unexpected subcommand" >&2\nexit 2\n' > "$old_cli"
  chmod +x "$old_cli"
  run bash -c 'source "$1"; verify_filesystem_probe_cli "$2"' _ "$REPO_ROOT/build/package-app.sh" "$old_cli"
  [ "$status" -ne 0 ]
  [[ "$output" == *"native filesystem metadata command is missing"* ]]
}
