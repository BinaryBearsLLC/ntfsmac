#!/usr/bin/env bats
# tests/cli/list-drives.bats — ext2/3/4 list support (NTFS + ext scope).
# Plan: widen the drive picker from `anylinuxfs list --microsoft` (ntfs/exfat/BitLocker only)
# to bare `anylinuxfs list` + a client-side allow-set {ntfs,exfat,BitLocker,ext2,ext3,ext4}.
# Surfaces ext partitions while keeping out-of-scope Linux FS (btrfs/xfs/zfs/LUKS/LVM) hidden.
# Mirrors gui/Tests/DriveScannerTests.swift's allowed-set tests — bash and Swift can't share
# source, two impls kept in sync deliberately (per cli/lib/list-drives.sh header comment).

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  STUB_DIR="$(mktemp -d)"
  # Stub behaves like the real anylinuxfs list: `list --microsoft` returns the server-side
  # Microsoft-only subset (current behavior); bare `list` returns the full unfiltered set
  # including ext + an out-of-scope btrfs row. This makes the RED state real — current code
  # calls `list --microsoft`, so ext4 is absent until the code switches to bare `list`.
  cat > "$STUB_DIR/anylinuxfs" <<STUB
#!/bin/bash
if [[ "\$1" == "list" && "\${2:-}" == "--microsoft" ]]; then
  printf '%s\n' '   1:                        ntfs MyDrive                  100.0 GB   disk2s1'
elif [[ "\$1" == "list" ]]; then
  printf '%s\n' \
    '   1:                        ntfs MyDrive                  100.0 GB   disk2s1' \
    '   2:                        ext4 LinuxVol                   50.0 GB   disk2s2' \
    '   3:                        btrfs BtrVol                    20.0 GB   disk2s3'
fi
exit 0
STUB
  chmod +x "$STUB_DIR/anylinuxfs"

  export NTFSMAC_ANYLINUXFS_BIN="$STUB_DIR/anylinuxfs"
  # shellcheck source=../../cli/lib/list-drives.sh
  source "$REPO_ROOT/cli/lib/list-drives.sh"
}

teardown() {
  rm -rf "$STUB_DIR"
}

@test "list_mountable_drives surfaces ext4 partitions alongside NTFS" {
  run list_mountable_drives
  [ "$status" -eq 0 ]
  [[ "$output" == *"disk2s1"* ]]   # NTFS still present
  [[ "$output" == *"disk2s2"* ]]   # ext4 now surfaced
  [[ "$output" == *"ext4"* ]]
}

@test "list_mountable_drives excludes out-of-scope filesystems (btrfs filtered client-side)" {
  run list_mountable_drives
  [[ "$output" != *"disk2s3"* ]]   # btrfs partition excluded
  # fstype is the 4th tab column; btrfs must not appear as a reported fstype
  ! grep -q $'\tbtrfs$' <<<"$output"
}

@test "list_mountable_drives surfaces NTFS with real multi-word 'Microsoft Basic Data' TYPE column" {
  # Real anylinuxfs list output for NTFS: blkid fs_type is empty in this build, so
  # darwin::augment_line falls back to the raw GPT type name "Microsoft Basic Data" for the
  # TYPE column (vendor/.../diskutil/darwin.rs: fs_type.unwrap_or(part_type)). A single-token
  # fstype capture grabs only "Microsoft" and the allow-set rejects the row — the regression
  # that dropped NTFS drives after commit 1be5bf2 removed --microsoft. The filter must match
  # the "Microsoft Basic Data" prefix, exactly what the server's --microsoft filter keys on.
  cat > "$STUB_DIR/anylinuxfs" <<STUB
#!/bin/bash
printf '%s\n' '   4:       Microsoft Basic Data Media                   224.2 GB   disk4s4'
exit 0
STUB
  chmod +x "$STUB_DIR/anylinuxfs"
  run list_mountable_drives
  [ "$status" -eq 0 ]
  [[ "$output" == *"disk4s4"* ]]
}

@test "list_mountable_drives surfaces unlabeled MBR NTFS with real Windows_NTFS TYPE column" {
  # Captured from a real 248 GB external MBR disk. Windows_NTFS is the partition type, not an
  # allow-listed blkid token; it must be normalized to ntfs rather than dropped.
  cat > "$STUB_DIR/anylinuxfs" <<STUB
#!/bin/bash
printf '%s\n' '   1:               Windows_NTFS                         248.0 GB   disk4s1'
exit 0
STUB
  chmod +x "$STUB_DIR/anylinuxfs"
  run list_mountable_drives
  [ "$status" -eq 0 ]
  [ "$output" = $'disk4s1\t\t248.0 GB\tntfs' ]
}

@test "list_mountable_drives preserves label from real MBR Windows_NTFS TYPE column" {
  # Captured from a second real 8.1 GB USB stick.
  cat > "$STUB_DIR/anylinuxfs" <<STUB
#!/bin/bash
printf '%s\n' '   1:               Windows_NTFS USB_8GB                 8.1 GB     disk5s1'
exit 0
STUB
  chmod +x "$STUB_DIR/anylinuxfs"
  run list_mountable_drives
  [ "$status" -eq 0 ]
  [ "$output" = $'disk5s1\tUSB_8GB\t8.1 GB\tntfs' ]
}

@test "list_mountable_drives calls anylinuxfs list without --microsoft" {
  CALL_LOG="$STUB_DIR/list.calls"
  cat > "$STUB_DIR/anylinuxfs" <<STUB
#!/bin/bash
echo "\$@" >> "$CALL_LOG"
printf '%s\n' '   1:                        ext4 LinuxVol                   50.0 GB   disk2s2'
exit 0
STUB
  chmod +x "$STUB_DIR/anylinuxfs"
  run list_mountable_drives
  [ "$status" -eq 0 ]
  run cat "$CALL_LOG"
  [[ "$output" == "list" ]]
  [[ "$output" != *"--microsoft"* ]]
}

@test "list_mountable_drives surfaces ext with real 'Linux Filesystem' TYPE column" {
  # Real anylinuxfs list output for ext when blkid can't resolve the superblock:
  # darwin::augment_line falls back to the raw GPT type name "Linux Filesystem" for the TYPE
  # column (vendor/.../diskutil/darwin.rs: fs_type.unwrap_or(part_type); GPT name in
  # LINUX_PART_TYPES, mod.rs:257). GPT type 0FC63DAF ("Linux Filesystem") covers ALL ext
  # versions — ext2, ext3, ext4 — Apple diskutil does not distinguish them. The single-token
  # fstype capture grabs only "Linux" and the allow-set rejects the row — the ext equivalent
  # of the NTFS "Microsoft Basic Data" regression. Fixture is the real output shape from
  # /usr/local/ntfsmac/bin/anylinuxfs list against an ext disk.
  cat > "$STUB_DIR/anylinuxfs" <<STUB
#!/bin/bash
printf '%s\n' '   1:                       Linux Filesystem              31.5 GB    disk4s1'
exit 0
STUB
  chmod +x "$STUB_DIR/anylinuxfs"
  run list_mountable_drives
  [ "$status" -eq 0 ]
  [[ "$output" == *"disk4s1"* ]]
  grep -q $'\text'$ <<<"$output"   # fstype column (last) reports generic "ext"
}

@test "list_mountable_drives surfaces ext 'Linux Filesystem' TYPE with label" {
  # Same GPT-name fallback but the partition carries a volume label. The parser must strip
  # the "Linux Filesystem" prefix and keep "MyVol", not treat "Filesystem" as the label.
  cat > "$STUB_DIR/anylinuxfs" <<STUB
#!/bin/bash
printf '%s\n' '   1:                       Linux Filesystem MyVol        31.5 GB    disk4s1'
exit 0
STUB
  chmod +x "$STUB_DIR/anylinuxfs"
  run list_mountable_drives
  [ "$status" -eq 0 ]
  [[ "$output" == *"disk4s1"* ]]
  [[ "$output" == *"MyVol"* ]]
  grep -q $'\text'$ <<<"$output"
}

@test "fs_type_for_device returns the fstype column for a given device" {
  # mount.sh reuses the same parse to decide --ignore-permissions for ext on the direct
  # mount path (no --fs-driver given). Must return the 4th tab column verbatim.
  run fs_type_for_device disk2s2
  [ "$status" -eq 0 ]
  [ "$output" == "ext4" ]
  run fs_type_for_device disk2s1
  [ "$status" -eq 0 ]
  [ "$output" == "ntfs" ]
}

@test "fs_type_for_device returns empty for an unknown device" {
  run fs_type_for_device disk9s9
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "list_mountable_drives excludes exfat (macOS reads/writes exFAT natively)" {
  # macOS already supports exFAT read/write, so ntfsmac must not surface exfat partitions —
  # only NTFS (needs write help), ext (unsupported by macOS), and BitLocker are in scope.
  cat > "$STUB_DIR/anylinuxfs" <<STUB
#!/bin/bash
printf '%s\n' \
  '   1:                        ntfs MyDrive                  100.0 GB   disk2s1' \
  '   2:                       exfat ExVol                     64.0 GB   disk2s2'
exit 0
STUB
  chmod +x "$STUB_DIR/anylinuxfs"
  run list_mountable_drives
  [ "$status" -eq 0 ]
  [[ "$output" == *"disk2s1"* ]]   # NTFS still present
  [[ "$output" != *"disk2s2"* ]]   # exfat partition excluded
  ! grep -q $'\texfat$' <<<"$output"
}
