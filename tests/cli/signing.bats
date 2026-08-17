#!/usr/bin/env bats
# tests/cli/signing.bats — 2-signing acceptance (PLAN.md §6, L4).
# Signs a fixture binary, verifies it, then tampers with it and asserts verification fails.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SIGN_SCRIPT="$REPO_ROOT/build/sign.sh"
  VERIFY_SCRIPT="$REPO_ROOT/build/verify-signature.sh"
  BIN_DIR="$(mktemp -d)"

  # Real Mach-O fixtures (codesign needs a real binary, not an arbitrary file) — copy
  # actual system binaries under the fixed names sign.sh/verify-signature.sh expect.
  cp /bin/echo "$BIN_DIR/anylinuxfs"
  cp /bin/cat "$BIN_DIR/gvproxy"
  cp /bin/ls "$BIN_DIR/init-rootfs"
  cp /bin/date "$BIN_DIR/vmnet-helper"
  chmod +x "$BIN_DIR/anylinuxfs" "$BIN_DIR/gvproxy" "$BIN_DIR/init-rootfs" "$BIN_DIR/vmnet-helper"

  export NTFSMAC_VENDOR_BIN_DIR="$BIN_DIR"
}

teardown() {
  rm -rf "$BIN_DIR"
}

@test "sign.sh exists and is executable" {
  [ -x "$SIGN_SCRIPT" ]
}

@test "verify-signature.sh exists and is executable" {
  [ -x "$VERIFY_SCRIPT" ]
}

@test "signs the fixtures ad-hoc and verify-signature.sh confirms it" {
  run "$SIGN_SCRIPT"
  [ "$status" -eq 0 ]
  run "$VERIFY_SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK — $BIN_DIR/anylinuxfs"* ]]
  [[ "$output" == *"OK — $BIN_DIR/gvproxy"* ]]
  [[ "$output" == *"OK — $BIN_DIR/init-rootfs"* ]]
  [[ "$output" == *"OK — $BIN_DIR/vmnet-helper"* ]]
}

@test "signs the macOS vmnet helper but never the Linux-only vmproxy" {
  run grep -F 'SIGNABLE=(anylinuxfs gvproxy init-rootfs vmnet-helper)' "$SIGN_SCRIPT"
  [ "$status" -eq 0 ]
  run grep -E '^SIGNABLE=.*vmproxy' "$SIGN_SCRIPT"
  [ "$status" -ne 0 ]
}

@test "anylinuxfs and init-rootfs get the hypervisor entitlement embedded; gvproxy does not" {
  run "$SIGN_SCRIPT"
  [ "$status" -eq 0 ]

  run codesign -d --entitlements - --xml "$BIN_DIR/anylinuxfs"
  [[ "$output" == *"com.apple.security.hypervisor"* ]]

  run codesign -d --entitlements - --xml "$BIN_DIR/init-rootfs"
  [[ "$output" == *"com.apple.security.hypervisor"* ]]

  run codesign -d --entitlements - --xml "$BIN_DIR/gvproxy"
  [[ "$output" != *"com.apple.security.hypervisor"* ]]

  run codesign -d --entitlements - --xml "$BIN_DIR/vmnet-helper"
  [[ "$output" == *"com.apple.security.virtualization"* ]]
}

@test "verify-signature.sh confirms the hypervisor entitlement is present" {
  run "$SIGN_SCRIPT"
  [ "$status" -eq 0 ]
  run "$VERIFY_SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"carries the hypervisor entitlement"* ]]
  [[ "$output" == *"carries the virtualization entitlement"* ]]
}

@test "defaults to ad-hoc signing and accepts an explicit release identity" {
  run grep -F 'SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"' "$SIGN_SCRIPT"
  [ "$status" -eq 0 ]
  run grep -F -- '--options runtime' "$SIGN_SCRIPT"
  [ "$status" -eq 0 ]
}

@test "a tampered (unsigned after modification) binary fails verification" {
  run "$SIGN_SCRIPT"
  [ "$status" -eq 0 ]
  # Append a byte after signing: invalidates the existing signature's code hash.
  printf '\x00' >> "$BIN_DIR/anylinuxfs"
  run "$VERIFY_SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL"* ]]
}

@test "verify-signature.sh fails on a missing binary" {
  rm "$BIN_DIR/gvproxy"
  run "$VERIFY_SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"missing"* ]]
}
