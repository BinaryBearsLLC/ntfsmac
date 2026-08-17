#!/usr/bin/env bats
# tests/cli/run-with-progress.bats — shared subprocess watchdog used by list-drives.sh,
# nfs-mount.sh, unmount.sh so no CLI operation can hang with zero feedback.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  LIB="$REPO_ROOT/cli/lib/run-with-progress.sh"
  source "$LIB"
}

@test "fast command returns immediately with its real exit code" {
  run run_with_progress 5 2 "test" - true
  [ "$status" -eq 0 ]
}

@test "propagates a real non-zero exit code, not a timeout" {
  run run_with_progress 5 2 "test" - false
  [ "$status" -eq 1 ]
}

@test "captures stdout to the given outfile" {
  local outfile
  outfile="$(mktemp)"
  run_with_progress 5 2 "test" "$outfile" echo "hello"
  [ "$(cat "$outfile")" = "hello" ]
  rm -f "$outfile"
}

@test "optionally captures stderr beside stdout for classified backend failures" {
  local outfile
  outfile="$(mktemp)"
  RUN_WITH_PROGRESS_CAPTURE_STDERR=1 run_with_progress 5 2 "test" "$outfile" \
    bash -c 'echo normal; echo classified-marker >&2; exit 7' || rc=$?
  [ "${rc:-0}" -eq 7 ]
  [ "$(cat "$outfile")" = $'normal\nclassified-marker' ]
  rm -f "$outfile"
}

@test "kills a hanging command after the timeout and returns 124 with a clear message" {
  run run_with_progress 1 1 "test-label" - sleep 30
  [ "$status" -eq 124 ]
  [[ "$output" == *"test-label"*"no response after 1s"* ]]
}

@test "does not leave the killed process running" {
  local stub pidfile victim_pid
  stub="$(mktemp)"
  pidfile="$(mktemp)"
  cat > "$stub" <<'STUB'
#!/bin/bash
sleep 30 &
printf '%s\n' "$!" > "$1"
wait
STUB
  chmod +x "$stub"

  run run_with_progress 1 1 "test" - "$stub" "$pidfile"

  [ "$status" -eq 124 ]
  victim_pid="$(cat "$pidfile")"
  sleep 1
  ! kill -0 "$victim_pid" 2>/dev/null
  rm -f "$stub" "$pidfile"
}

@test "timeout terminates descendants that ignore TERM" {
  local stub pidfile nested_pid nested_sleep_pid
  stub="$(mktemp)"
  pidfile="$(mktemp)"
  cat > "$stub" <<'STUB'
#!/bin/bash
trap '' TERM
(
  trap '' TERM
  sleep 30 &
  printf '%s\n' "$!" > "$1.sleep"
  wait
) &
printf '%s\n' "$!" > "$1"
wait
STUB
  chmod +x "$stub"

  run run_with_progress 1 1 "nested-test" - "$stub" "$pidfile"

  [ "$status" -eq 124 ]
  nested_pid="$(cat "$pidfile")"
  nested_sleep_pid="$(cat "$pidfile.sleep")"
  sleep 1
  ! kill -0 "$nested_pid" 2>/dev/null
  ! kill -0 "$nested_sleep_pid" 2>/dev/null
  rm -f "$stub" "$pidfile" "$pidfile.sleep"
}

@test "prints a heartbeat line while a slow-but-eventually-completing command runs" {
  run run_with_progress 5 1 "test-label" - sleep 2
  [ "$status" -eq 0 ]
  [[ "$output" == *"test-label: still working"* ]]
}
