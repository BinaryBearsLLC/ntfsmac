#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  STUB_DIR="$(mktemp -d)"
  export NTFSMAC_ANYLINUXFS_BIN="$STUB_DIR/anylinuxfs"
  export NTFSMAC_SKIP_ROOT_CHECK=1
  cat > "$NTFSMAC_ANYLINUXFS_BIN" <<'SH'
#!/bin/bash
if [[ "$1" == --help ]]; then echo probe-filesystem; exit 0; fi
[[ "$#" == 2 && "$1" == probe-filesystem && "$2" == disk4s2 ]] || exit 99
printf '%s\n' '{"device":"disk4s2","fs_type":"ext4","label":"rootfs"}'
SH
  chmod +x "$NTFSMAC_ANYLINUXFS_BIN"
}

@test "filesystem rejects an older runtime before its implicit mount fallback" {
  cat > "$NTFSMAC_ANYLINUXFS_BIN" <<'SH'
#!/bin/bash
if [[ "$1" == --help ]]; then echo 'mount unmount list'; exit 0; fi
echo 'UNSAFE DEFAULT MOUNT FALLBACK'
exit 99
SH
  run bash "$REPO_ROOT/cli/commands/filesystem.sh" disk4s2
  [ "$status" -eq 1 ]
  [[ "$output" == *"runtime is outdated"* ]]
  [[ "$output" != *"UNSAFE DEFAULT"* ]]
}

@test "filesystem bounds a stalled runtime capability check" {
  printf '#!/bin/sh\nexec sleep 30\n' > "$NTFSMAC_ANYLINUXFS_BIN"
  local started=$SECONDS
  run bash "$REPO_ROOT/cli/commands/filesystem.sh" disk4s2
  [ "$status" -eq 1 ]
  [[ "$output" == *"could not check runtime support"* ]]
  [ "$((SECONDS - started))" -lt 6 ]
}

teardown() { rm -rf "$STUB_DIR"; }

@test "filesystem reports native superblock metadata without a mount command" {
  run bash "$REPO_ROOT/cli/commands/filesystem.sh" disk4s2
  [ "$status" -eq 0 ]
  [ "$output" = '{"device":"disk4s2","fs_type":"ext4","label":"rootfs"}' ]
}

@test "filesystem rejects paths whole disks injection and extra arguments" {
  for device in /dev/disk4s2 disk4 'disk4s2;id' ''; do
    run bash "$REPO_ROOT/cli/commands/filesystem.sh" "$device"
    [ "$status" -ne 0 ]
    [[ "$output" == *"rejected"* || "$output" == *"usage:"* ]]
  done
  run bash "$REPO_ROOT/cli/commands/filesystem.sh" disk4s2 disk4s3
  [ "$status" -ne 0 ]
  [[ "$output" == *"usage:"* ]]
}
