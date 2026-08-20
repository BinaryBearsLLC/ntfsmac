#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  RUNNER="$REPO_ROOT/build/run-swift-tests.sh"
  STUB="$(mktemp)"
  SCRATCH="$(mktemp -d)"
  chmod +x "$STUB"
}

teardown() {
  rm -f -- "$STUB" "${STUB}.args" "${STUB}.pid"
  rm -rf -- "$SCRATCH"
}

@test "skips only the named render suite on the affected macOS release" {
  cat > "$STUB" <<'STUB'
#!/bin/bash
printf '%s\n' "$@" > "${0}.args"
echo 'Test run with 278 tests in 3 suites passed after 0.5 seconds.'
STUB

  run env NTFSMAC_SWIFT_TEST_EXECUTABLE="$STUB" NTFSMAC_TEST_MACOS_VERSION=26.6.2 \
    "$RUNNER" modern "$SCRATCH"

  [ "$status" -eq 0 ]
  grep -Fxq -- '--skip' "${STUB}.args"
  grep -Fxq -- 'PopoverStateRenderTests' "${STUB}.args"
}

@test "keeps render tests enabled on unaffected macOS releases" {
  cat > "$STUB" <<'STUB'
#!/bin/bash
printf '%s\n' "$@" > "${0}.args"
echo 'Test run with 291 tests in 3 suites passed after 0.5 seconds.'
STUB

  run env NTFSMAC_SWIFT_TEST_EXECUTABLE="$STUB" NTFSMAC_TEST_MACOS_VERSION=26.6.1 \
    "$RUNNER" modern "$SCRATCH"

  [ "$status" -eq 0 ]
  ! grep -Fxq -- '--skip' "${STUB}.args"
  ! grep -Fxq -- 'PopoverStateRenderTests' "${STUB}.args"
}

@test "accepts a normally completed non-empty Swift test run" {
  cat > "$STUB" <<'STUB'
#!/bin/bash
echo 'Test run with 291 tests in 3 suites passed after 0.5 seconds.'
STUB

  run env NTFSMAC_SWIFT_TEST_EXECUTABLE="$STUB" "$RUNNER" modern "$SCRATCH"

  [ "$status" -eq 0 ]
}

@test "propagates a real test failure" {
  cat > "$STUB" <<'STUB'
#!/bin/bash
echo 'Test run with 290 tests in 3 suites failed after 0.5 seconds.'
exit 1
STUB

  run env NTFSMAC_SWIFT_TEST_EXECUTABLE="$STUB" "$RUNNER" legacy "$SCRATCH"

  [ "$status" -eq 1 ]
}

@test "rejects a zero-test or missing completion summary" {
  cat > "$STUB" <<'STUB'
#!/bin/bash
echo 'Build complete! (0.1s)'
STUB

  run env NTFSMAC_SWIFT_TEST_EXECUTABLE="$STUB" "$RUNNER" modern "$SCRATCH"

  [ "$status" -eq 1 ]
  [[ "$output" == *"refusing to package the GUI"* ]]
}

@test "closes only the runner subtree when Swift hangs after the passed summary" {
  cat > "$STUB" <<'STUB'
#!/bin/bash
echo 'Test run with 291 tests in 3 suites passed after 0.5 seconds.'
sleep 30 &
echo "$!" > "${0}.pid"
wait
STUB

  run env NTFSMAC_SWIFT_TEST_EXECUTABLE="$STUB" \
    NTFSMAC_SWIFT_TEST_SUMMARY_GRACE=1 "$RUNNER" modern "$SCRATCH"

  [ "$status" -eq 0 ]
  [[ "$output" == *"closing an unresponsive SwiftPM test helper"* ]]
  child_pid="$(cat "${STUB}.pid")"
  sleep 1
  ! kill -0 "$child_pid" 2>/dev/null
}

@test "times out and fails when no terminal summary appears" {
  cat > "$STUB" <<'STUB'
#!/bin/bash
echo 'Running tests...'
sleep 30
STUB

  run env NTFSMAC_SWIFT_TEST_EXECUTABLE="$STUB" \
    NTFSMAC_SWIFT_TEST_TIMEOUT=1 "$RUNNER" modern "$SCRATCH"

  [ "$status" -eq 124 ]
  [[ "$output" == *"did not finish within 1s"* ]]
}
