#!/usr/bin/env bats
# tests/build/github-actions.bats — immutable root-workflow action acceptance checks.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  LOCK_SH="$REPO_ROOT/build/lib/lock.sh"
  WORKFLOWS=(
    "$REPO_ROOT/.github/workflows/ci.yml"
    "$REPO_ROOT/.github/workflows/pages.yml"
    "$REPO_ROOT/.github/workflows/release.yml"
  )
}

@test "all root workflows pin actions/checkout to the reviewed full commit" {
  local expected refs
  expected="$($LOCK_SH get ACTIONS_CHECKOUT_COMMIT)"
  [[ "$expected" =~ ^[0-9a-f]{40}$ ]]
  refs="$(grep -hE 'uses: actions/checkout@' "${WORKFLOWS[@]}" |
    sed -E 's/.*@([0-9a-f]{40}).*/\1/')"
  [ "$(wc -l <<< "$refs" | tr -d ' ')" -eq 5 ]
  run grep -Ev "^${expected}$" <<< "$refs"
  [ "$status" -ne 0 ]
}

@test "root workflows contain no floating checkout ref" {
  run grep -hE 'uses: actions/checkout@(v[0-9]+|main|master)$' "${WORKFLOWS[@]}"
  [ "$status" -ne 0 ]
}

@test "CI and release pin actions/setup-go to the reviewed full commit" {
  local expected refs
  expected="$($LOCK_SH get ACTIONS_SETUP_GO_COMMIT)"
  [[ "$expected" =~ ^[0-9a-f]{40}$ ]]
  refs="$(grep -hE 'uses: actions/setup-go@' "${WORKFLOWS[@]}" |
    sed -E 's/.*@([0-9a-f]{40}).*/\1/')"
  [ "$(wc -l <<< "$refs" | tr -d ' ')" -eq 2 ]
  run grep -Ev "^${expected}$" <<< "$refs"
  [ "$status" -ne 0 ]
}

@test "root workflows contain no floating setup-go ref" {
  run grep -hE 'uses: actions/setup-go@(v[0-9]+|main|master)$' "${WORKFLOWS[@]}"
  [ "$status" -ne 0 ]
}
