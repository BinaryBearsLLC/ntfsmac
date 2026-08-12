#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SCRIPT="$REPO_ROOT/cli/commands/opengui.sh"
  FIXTURE_DIR="$(mktemp -d)"
  export NTFSMAC_OPEN_BIN="$FIXTURE_DIR/open"
  export NTFSMAC_OPEN_CALLS="$FIXTURE_DIR/open.calls"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "$NTFSMAC_OPEN_CALLS"\nexit "${NTFSMAC_OPEN_EXIT:-0}"\n' > "$NTFSMAC_OPEN_BIN"
  chmod +x "$NTFSMAC_OPEN_BIN"
}

teardown() {
  rm -rf "$FIXTURE_DIR"
}

@test "requests the installed GUI by bundle identifier" {
  run "$SCRIPT"

  [ "$status" -eq 0 ]
  [ "$(cat "$NTFSMAC_OPEN_CALLS")" = $'-b com.khr898.ntfsmac binarybears-ntfsmac://opengui\n-b com.khr898.ntfsmac binarybears-ntfsmac://opengui\n-b com.khr898.ntfsmac binarybears-ntfsmac://opengui' ]
  [[ "$output" == *"popover requested"* ]]
}

@test "supports an explicit app bundle for development builds" {
  export NTFSMAC_GUI_APP_PATH="$FIXTURE_DIR/ntfsmac.app"
  mkdir "$NTFSMAC_GUI_APP_PATH"

  run "$SCRIPT"

  [ "$status" -eq 0 ]
  [ "$(cat "$NTFSMAC_OPEN_CALLS")" = $'-a '"$NTFSMAC_GUI_APP_PATH"$' binarybears-ntfsmac://opengui\n-a '"$NTFSMAC_GUI_APP_PATH"$' binarybears-ntfsmac://opengui\n-a '"$NTFSMAC_GUI_APP_PATH"$' binarybears-ntfsmac://opengui' ]
}

@test "fails clearly when Launch Services cannot find the app" {
  export NTFSMAC_OPEN_EXIT=1

  run "$SCRIPT"

  [ "$status" -ne 0 ]
  [[ "$output" == *"not installed or registered"* ]]
}

@test "help and invalid arguments never launch the app" {
  run "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [ ! -e "$NTFSMAC_OPEN_CALLS" ]

  run "$SCRIPT" unexpected
  [ "$status" -eq 2 ]
  [ ! -e "$NTFSMAC_OPEN_CALLS" ]
}
