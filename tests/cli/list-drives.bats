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

@test "MBR SSD exposes every Linux sibling and preserves unlabeled filesystem routing" {
  cat > "$STUB_DIR/anylinuxfs" <<'STUB'
#!/bin/bash
cat <<'OUTPUT'
/dev/disk4 (external, physical):
   #:                       TYPE NAME                    SIZE       IDENTIFIER
   0:     FDisk_partition_scheme                        *1.0 TB     disk4
   1:             Windows_FAT_32 bootfs                  536.9 MB   disk4s1
   2:                      Linux                         124.0 GB   disk4s2
   3:                      Linux                         875.7 GB   disk4s3
OUTPUT
STUB
  run list_mountable_drives
  [ "$status" -eq 0 ]
  [ "$output" = $'disk4s2\t\t124.0 GB\text\ndisk4s3\t\t875.7 GB\text' ]
  run fs_type_for_device disk4s2
  [ "$output" = ext ]
  run fs_type_for_device disk4s3
  [ "$output" = ext ]
}

@test "MBR Linux fallback preserves labels and excludes LVM RAID swap and unsupported filesystems" {
  cat > "$STUB_DIR/anylinuxfs" <<'STUB'
#!/bin/bash
cat <<'OUTPUT'
   1:                      Linux My Linux Volume          12.0 GB   disk5s1
   2:                  Linux LVM                          12.0 GB   disk5s2
   3:                  Linux_LVM                          12.0 GB   disk5s3
   4:                 Linux_RAID                          12.0 GB   disk5s4
   5:                 Linux Swap                          12.0 GB   disk5s5
   6:                      btrfs                          12.0 GB   disk5s6
   7:                crypto_LUKS                          12.0 GB   disk5s7
   8:                      Linux                          12.0 GB   disk5
OUTPUT
STUB
  run list_mountable_drives
  [ "$status" -eq 0 ]
  [ "$output" = $'disk5s1\tMy Linux Volume\t12.0 GB\text' ]
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

@test "list_mountable_drives rejects unresolved Microsoft Basic Data partition type" {
  # GPT basic data is shared by NTFS and exFAT.
  cat > "$STUB_DIR/anylinuxfs" <<STUB
#!/bin/bash
printf '%s\n' '   4:       Microsoft Basic Data Media                   224.2 GB   disk4s4'
exit 0
STUB
  chmod +x "$STUB_DIR/anylinuxfs"
  run list_mountable_drives
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "list_mountable_drives rejects unresolved unlabeled Windows_NTFS partition type" {
  # MBR 0x07 also hosts exFAT.
  cat > "$STUB_DIR/anylinuxfs" <<STUB
#!/bin/bash
printf '%s\n' '   1:               Windows_NTFS                         248.0 GB   disk4s1'
exit 0
STUB
  chmod +x "$STUB_DIR/anylinuxfs"
  run list_mountable_drives
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "list_mountable_drives rejects unresolved labeled Windows_NTFS partition type" {
  # Captured from a second real 8.1 GB USB stick.
  cat > "$STUB_DIR/anylinuxfs" <<STUB
#!/bin/bash
printf '%s\n' '   1:               Windows_NTFS USB_8GB                 8.1 GB     disk5s1'
exit 0
STUB
  chmod +x "$STUB_DIR/anylinuxfs"
  run list_mountable_drives
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "mixed devices retain only independently confirmed NTFS and exclude exFAT and unknown" {
  cat > "$STUB_DIR/anylinuxfs" <<'STUB'
#!/bin/bash
printf '%s\n' \
 '   1:                        ntfs MobileData              123.0 GB   disk4s1' \
 '   1:                       exfat Retroid_SD               62.5 GB   disk5s1' \
 '   1:               Windows_NTFS TEST_USB                123.0 GB   disk6s1' \
 '   1:                     Unknown UnknownVolume            32.0 GB   disk7s1'
STUB
  run list_mountable_drives
  [ "$status" -eq 0 ]
  [ "$output" = $'disk4s1\tMobileData\t123.0 GB\tntfs' ]
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

@test "fs_type_for_device returns ext4 for an UNLABELED ext4 drive (empty label field not collapsed)" {
  # Regression guard: an unlabeled ext4 partition (mkfs.ext4 without -L) makes anylinuxfs list
  # emit a TYPE column of "ext4" with NO volume label, so list_mountable_drives prints
  # `disk4s1\t\t31.5 GB\text4` — an EMPTY label field (two consecutive tabs). Parsing that with
  # `IFS=$'\t' read` collapses the empty field (tab is whitespace IFS), shifting size->label,
  # fstype->size, and fstype becomes "". The probe then returns empty, mount.sh never sets
  # --ignore-permissions, the NFS mount gets no noowners, and ext is read-only — the bug that
  # made CLI ext mounts unwritable while the GUI (Swift split(separator:), no collapse) worked.
  # Manual parameter-expansion split preserves the empty field. Must return ext4, not "".
  cat > "$STUB_DIR/anylinuxfs" <<STUB
#!/bin/bash
printf '%s\n' '   1:                        ext4                         31.5 GB    disk4s1'
exit 0
STUB
  chmod +x "$STUB_DIR/anylinuxfs"
  run fs_type_for_device disk4s1
  [ "$status" -eq 0 ]
  [ "$output" == "ext4" ]
  # And list_mountable_drives must report ext4 as the fstype (4th tab column), not drop it.
  run list_mountable_drives
  [ "$status" -eq 0 ]
  grep -q $'\text4$' <<<"$output"
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
