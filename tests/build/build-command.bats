#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SCRIPT="$REPO_ROOT/build.command"
}

@test "builder documents automatic standard and Legacy GUI outputs" {
  run "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"standard and Legacy"* ]]
  [[ "$output" == *"--no-legacy"* ]]
  [[ "$output" == *"automatically produces both"* ]]
}

@test "builder rejects an unknown second option before running build tools" {
  run "$SCRIPT" gui --unknown
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unknown option '--unknown'"* ]]
}

@test "builder rejects extra arguments before running build tools" {
  run "$SCRIPT" gui --no-legacy unexpected
  [ "$status" -ne 0 ]
  [[ "$output" == *"Too many arguments"* ]]
}

@test "builder wires isolated modern and Legacy variants and the opt-out gate" {
  run grep -F 'NTFSMAC_HELPER_VARIANT=modern' "$SCRIPT"
  [ "$status" -eq 0 ]
  run grep -F 'NTFSMAC_HELPER_VARIANT=legacy' "$SCRIPT"
  [ "$status" -eq 0 ]
  run grep -F 'LEGACY_ENABLED' "$SCRIPT"
  [ "$status" -eq 0 ]
  run grep -F 'An explicit opt-out must not leave a prior Legacy build' "$SCRIPT"
  [ "$status" -eq 0 ]
  run grep -F 'helperSwiftSettings' "$REPO_ROOT/Package.swift"
  [ "$status" -eq 0 ]
}
