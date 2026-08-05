#!/usr/bin/env bats
# tests/cli/mount.bats — 2-mount acceptance (PLAN.md §6, L1, L3, L6).
# Mocks anylinuxfs (records argv) and mount_nfs (proves our layer never shells out to it
# directly — anylinuxfs owns the host NFS mount internally, see cli/lib/nfs-mount.sh).

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SCRIPT="$REPO_ROOT/cli/commands/mount.sh"
  STUB_DIR="$(mktemp -d)"
  CALL_LOG="$STUB_DIR/anylinuxfs.calls"

  cat > "$STUB_DIR/anylinuxfs" <<STUB
#!/bin/bash
echo "\$@" >> "$CALL_LOG"
exit 0
STUB
  chmod +x "$STUB_DIR/anylinuxfs"

  cat > "$STUB_DIR/mount_nfs" <<STUB
#!/bin/bash
echo "\$@" >> "$STUB_DIR/mount_nfs.calls"
exit 0
STUB
  chmod +x "$STUB_DIR/mount_nfs"

  cat > "$STUB_DIR/diskutil" <<STUB
#!/bin/bash
echo "\$@" >> "$STUB_DIR/diskutil.calls"
exit 1
STUB
  chmod +x "$STUB_DIR/diskutil"

  export PATH="$STUB_DIR:$PATH"
  export NTFSMAC_SKIP_ROOT_CHECK=1
  export HOME="$STUB_DIR/home"
  mkdir -p "$HOME/.anylinuxfs/alpine"
  # Every other test in this file stubs anylinuxfs's exit code directly and isn't testing the
  # independent post-mount NFS-presence check — this repo's real `mount` table is out of scope
  # for those. The two dedicated tests for that check below unset this and stub `mount` too.
  export NTFSMAC_SKIP_MOUNT_VERIFY=1
}

teardown() {
  rm -rf "$STUB_DIR"
}

@test "mounts a valid device with soft NFS mode, hard never emitted" {
  run "$SCRIPT" disk2s1
  [ "$status" -eq 0 ]
  [ -f "$CALL_LOG" ]
  run cat "$CALL_LOG"
  [[ "$output" == *"soft"* ]]
  [[ "$output" != *"hard"* ]]
  [[ "$output" == *"/dev/disk2s1"* ]]
}

@test "rejects invalid device before ever invoking anylinuxfs" {
  run "$SCRIPT" "disk2s1; rm -rf /"
  [ "$status" -ne 0 ]
  [ ! -f "$CALL_LOG" ]
}

@test "does not shell out to mount_nfs directly (anylinuxfs owns the host NFS mount)" {
  run "$SCRIPT" disk2s1
  [ "$status" -eq 0 ]
  [ ! -f "$STUB_DIR/mount_nfs.calls" ]
}

@test "propagates anylinuxfs failure as a non-zero exit" {
  cat > "$STUB_DIR/anylinuxfs" <<STUB
#!/bin/bash
echo "\$@" >> "$CALL_LOG"
exit 1
STUB
  chmod +x "$STUB_DIR/anylinuxfs"
  run "$SCRIPT" disk2s1
  [ "$status" -ne 0 ]
}

@test "passes a custom mount point through when given" {
  run "$SCRIPT" disk2s1 /Volumes/MyDrive
  [ "$status" -eq 0 ]
  run cat "$CALL_LOG"
  [[ "$output" == *"/Volumes/MyDrive"* ]]
}

@test "absent --read-only keeps plain soft NFS options" {
  run "$SCRIPT" disk2s1
  [ "$status" -eq 0 ]
  run cat "$CALL_LOG"
  [[ "$output" == *"--nfs-options soft"* ]]
  [[ "$output" != *"ro"* ]]
}

@test "--read-only appends ro to --nfs-options, client-side enforcement" {
  run "$SCRIPT" --read-only disk2s1
  [ "$status" -eq 0 ]
  run cat "$CALL_LOG"
  [[ "$output" == *"--nfs-options soft,ro"* ]]
}

# Throughput tuning (PLAN.md L8 owner-override, default-on): rsize/wsize/readahead are
# always appended to --nfs-options — not opt-in. Near-zero risk (transfer-unit size +
# read-ahead; kernel auto-negotiates down; no integrity path), documented as the explicit
# L8 override in README + docs/dev/PLAN.md. See throughput-tuning.tdd.md.
@test "always appends rsize/wsize/readahead tuning (default mount)" {
  run "$SCRIPT" disk2s1
  [ "$status" -eq 0 ]
  run cat "$CALL_LOG"
  [[ "$output" == *"rsize=1048576"* ]]
  [[ "$output" == *"wsize=1048576"* ]]
  [[ "$output" == *"readahead=16"* ]]
  # rsize == wsize: macOS mount_nfs warns on a high wsize/rsize ratio ("unexpected readahead
  # RPCs"); keep them equal.
  [[ "$output" == *"rsize=1048576,wsize=1048576"* ]]
}

@test "tuning is present alongside --read-only (soft,ro,...,rsize=...)" {
  run "$SCRIPT" --read-only disk2s1
  [ "$status" -eq 0 ]
  run cat "$CALL_LOG"
  [[ "$output" == *"--nfs-options soft,ro,"* ]]
  [[ "$output" == *"rsize=1048576"* ]]
  [[ "$output" == *"wsize=1048576"* ]]
  [[ "$output" == *"readahead=16"* ]]
}

@test "auto-ejects the partition from macOS before mounting (diskutil unmount, not eject)" {
  run "$SCRIPT" disk2s1
  [ "$status" -eq 0 ]
  [ -f "$STUB_DIR/diskutil.calls" ]
  run cat "$STUB_DIR/diskutil.calls"
  [[ "$output" == "unmount /dev/disk2s1" ]]
}

@test "a diskutil unmount failure (wasn't mounted by macOS) doesn't block the real mount" {
  run "$SCRIPT" disk2s1
  [ "$status" -eq 0 ]
  [ -f "$CALL_LOG" ]
}

@test "no device given: lists compatible drives and mounts the chosen one" {
  cat > "$STUB_DIR/anylinuxfs" <<STUB
#!/bin/bash
if [[ "\$1" == "list" ]]; then
  echo "   1:                        ntfs MyDrive                  100.0 GB   disk2s1"
  echo "   2:                        ext4 OtherDrive                32.0 GB   disk3s2"
  exit 0
fi
echo "\$@" >> "$CALL_LOG"
exit 0
STUB
  chmod +x "$STUB_DIR/anylinuxfs"

  run "$SCRIPT" <<< "2"
  [ "$status" -eq 0 ]
  run cat "$CALL_LOG"
  [[ "$output" == *"/dev/disk3s2"* ]]
}

@test "no device given, no compatible drives: clear message, no anylinuxfs mount call" {
  run "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no compatible drives found"* ]]
  # CALL_LOG may contain the picker's own "list --microsoft" probe; it must never contain
  # an actual "mount" invocation.
  [[ "$(cat "$CALL_LOG" 2>/dev/null)" != *"mount"* ]]
}

@test "no device given, empty input at the prompt: cancels without mounting" {
  cat > "$STUB_DIR/anylinuxfs" <<STUB
#!/bin/bash
if [[ "\$1" == "list" ]]; then
  echo "   1:                        ntfs MyDrive                  100.0 GB   disk2s1"
  exit 0
fi
echo "\$@" >> "$CALL_LOG"
exit 0
STUB
  chmod +x "$STUB_DIR/anylinuxfs"

  run "$SCRIPT" <<< ""
  [ "$status" -ne 0 ]
  [[ "$output" == *"cancelled"* ]]
  [ ! -f "$CALL_LOG" ]
}

@test "first run: prints a one-time-setup notice when no Alpine cache exists" {
  rm -rf "$HOME/.anylinuxfs"
  run "$SCRIPT" disk2s1
  [ "$status" -eq 0 ]
  [[ "$output" == *"first run"* ]]
}

@test "legacy cache: prints the side-by-side migration notice rather than a first-run notice" {
  run "$SCRIPT" disk2s1
  [ "$status" -eq 0 ]
  [[ "$output" != *"first run"* ]]
  [[ "$output" == *"legacy Alpine cache detected and preserved"* ]]
}

@test "treats a false 'success' as failure when anylinuxfs exits 0 but no NFS mount actually exists" {
  unset NTFSMAC_SKIP_MOUNT_VERIFY
  cat > "$STUB_DIR/mount" <<'STUB'
#!/bin/bash
exit 0
STUB
  chmod +x "$STUB_DIR/mount"
  run "$SCRIPT" disk2s1
  [ "$status" -ne 0 ]
  [[ "$output" == *"no NFS mount is present"* ]]
}

@test "real success: anylinuxfs exits 0 and an NFS mount is actually present" {
  unset NTFSMAC_SKIP_MOUNT_VERIFY
  cat > "$STUB_DIR/mount" <<'STUB'
#!/bin/bash
echo "192.168.127.2:/export/a on /Volumes/MyDrive (nfs, nodev, nosuid)"
STUB
  chmod +x "$STUB_DIR/mount"
  run "$SCRIPT" disk2s1
  [ "$status" -eq 0 ]
  [[ "$output" == *"mounted"* ]]
}

@test "a wedged anylinuxfs mount gets killed and reported instead of hanging forever" {
  cat > "$STUB_DIR/anylinuxfs" <<STUB
#!/bin/bash
echo "\$@" >> "$CALL_LOG"
sleep 30
STUB
  chmod +x "$STUB_DIR/anylinuxfs"
  export NTFSMAC_MOUNT_TIMEOUT=1
  run "$SCRIPT" disk2s1
  [ "$status" -ne 0 ]
  [[ "$output" == *"no response after 1s"* ]]
}

@test "auto-passes --ignore-permissions for an ext drive on the direct path (probed fstype)" {
  # mount.sh probes fs_type_for_device when no --fs-driver is given; an ext drive needs
  # --ignore-permissions so the NFS export gets all_squash and the macOS user can write past
  # ext's Unix ownership. The probe reuses list_mountable_drives, so the stub must answer `list`.
  cat > "$STUB_DIR/anylinuxfs" <<STUB
#!/bin/bash
if [[ "\$1" == "list" ]]; then
  printf '%s\n' '   1:                       Linux Filesystem MyVol        31.5 GB    disk4s1'
  exit 0
fi
echo "\$@" >> "$CALL_LOG"
exit 0
STUB
  chmod +x "$STUB_DIR/anylinuxfs"

  run "$SCRIPT" disk4s1
  [ "$status" -eq 0 ]
  run cat "$CALL_LOG"
  [[ "$output" == *"--ignore-permissions"* ]]
}

@test "does not pass --ignore-permissions for an NTFS drive on the direct path" {
  # NTFS must NOT get all_squash — ntfs-3g already remaps uid/gid, and the user instruction is
  # "do not change on the NTFS part". A probed ntfs fstype leaves --ignore-permissions off.
  cat > "$STUB_DIR/anylinuxfs" <<STUB
#!/bin/bash
if [[ "\$1" == "list" ]]; then
  printf '%s\n' '   1:       Microsoft Basic Data MyDrive                100.0 GB   disk2s1'
  exit 0
fi
echo "\$@" >> "$CALL_LOG"
exit 0
STUB
  chmod +x "$STUB_DIR/anylinuxfs"

  run "$SCRIPT" disk2s1
  [ "$status" -eq 0 ]
  run cat "$CALL_LOG"
  [[ "$output" != *"--ignore-permissions"* ]]
}

@test "explicit --ignore-permissions flag is forwarded to anylinuxfs and skips the probe" {
  # The GUI helper passes --ignore-permissions for ext (its signal that the drive is ext-family,
  # avoiding a second `anylinuxfs list` probe). mount.sh must forward it as-is.
  cat > "$STUB_DIR/anylinuxfs" <<STUB
#!/bin/bash
echo "\$@" >> "$CALL_LOG"
exit 0
STUB
  chmod +x "$STUB_DIR/anylinuxfs"

  run "$SCRIPT" --ignore-permissions disk4s1
  [ "$status" -eq 0 ]
  run cat "$CALL_LOG"
  [[ "$output" == *"--ignore-permissions"* ]]
}

@test "picker-chosen ext drive gets --ignore-permissions (no extra probe)" {
  # Picker already has the fstype column from list_mountable_drives, so it does not re-probe;
  # it threads the fstype straight into the --ignore-permissions decision.
  cat > "$STUB_DIR/anylinuxfs" <<STUB
#!/bin/bash
if [[ "\$1" == "list" ]]; then
  printf '%s\n' \
    '   1:                        ntfs WinVol                      100.0 GB   disk2s1' \
    '   2:                       ext4 LinuxVol                      50.0 GB   disk3s2'
  exit 0
fi
echo "\$@" >> "$CALL_LOG"
exit 0
STUB
  chmod +x "$STUB_DIR/anylinuxfs"

  run "$SCRIPT" <<< "2"
  [ "$status" -eq 0 ]
  run cat "$CALL_LOG"
  [[ "$output" == *"/dev/disk3s2"* ]]
  [[ "$output" == *"--ignore-permissions"* ]]
}

@test "self-elevates via sudo when not root, instead of erroring or hitting anylinuxfs's cryptic probe error" {
  cat > "$STUB_DIR/sudo" <<STUB
#!/bin/bash
echo "\$@" >> "$STUB_DIR/sudo.calls"
exit 0
STUB
  chmod +x "$STUB_DIR/sudo"

  unset NTFSMAC_SKIP_ROOT_CHECK
  run "$SCRIPT" disk2s1
  [ "$status" -eq 0 ]
  [ -f "$STUB_DIR/sudo.calls" ]
  run cat "$STUB_DIR/sudo.calls"
  [[ "$output" == *"mount.sh"* ]]
  [[ "$output" == *"disk2s1"* ]]
  [ ! -f "$CALL_LOG" ]
}
