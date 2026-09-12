#!/usr/bin/env bats

@test "offline payload verification rejects corruption, escapes, missing and mismatched artifacts" {
  run python3 "$BATS_TEST_DIRNAME/offline_runtime_test.py"
  [ "$status" -eq 0 ]
}
