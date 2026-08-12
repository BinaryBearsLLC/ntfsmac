#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SCRIPT="$REPO_ROOT/cli/lib/mount-diagnostics.sh"
  FIXTURE_DIR="$(mktemp -d)"
  export NTFSMAC_MOUNT_DIAGNOSTICS_FILE="$FIXTURE_DIR/mount-diagnostics"
}

teardown() { rm -rf "$FIXTURE_DIR"; }

@test "publishes and reloads only a fixed driver and failure category" {
  run bash -c "source '$SCRIPT'; mount_diagnostics_publish ntfs3 backend_failed; mount_diagnostics_load; printf '%s|%s\n' \"\$MOUNT_DIAGNOSTICS_DRIVER\" \"\$MOUNT_DIAGNOSTICS_FAILURE\""
  [ "$status" -eq 0 ]
  [ "$output" = "ntfs3|backend_failed" ]
  run grep -E 'disk[0-9]|/Volumes/|bridge|172\.' "$NTFSMAC_MOUNT_DIAGNOSTICS_FILE"
  [ "$status" -ne 0 ]
}

@test "unknown keys and free-form failure text fail closed" {
  printf 'schema=1\nselected_driver=ntfs3\nfailure_category=Windows volume dirty\n' > "$NTFSMAC_MOUNT_DIAGNOSTICS_FILE"
  run bash -c "source '$SCRIPT'; mount_diagnostics_load"
  [ "$status" -ne 0 ]
  printf 'schema=1\nselected_driver=ntfs3\nfailure_category=none\ndevice=disk2s1\n' > "$NTFSMAC_MOUNT_DIAGNOSTICS_FILE"
  run bash -c "source '$SCRIPT'; mount_diagnostics_load"
  [ "$status" -ne 0 ]
}

@test "a group-or-world-writable diagnostic fails closed" {
  printf 'schema=1\nselected_driver=ntfs3\nfailure_category=none\n' > "$NTFSMAC_MOUNT_DIAGNOSTICS_FILE"
  chmod 666 "$NTFSMAC_MOUNT_DIAGNOSTICS_FILE"

  run bash -c "source '$SCRIPT'; mount_diagnostics_load"

  [ "$status" -ne 0 ]
}
