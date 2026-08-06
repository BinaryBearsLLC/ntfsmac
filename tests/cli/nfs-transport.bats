#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SCRIPT="$REPO_ROOT/tests/live/verify-nfs-transport.sh"
  export NTFSMAC_LIVE_PLATFORM_OVERRIDE="Darwin"
  export NTFSMAC_LIVE_VMNET_RUNNING_OVERRIDE="1"
  export NTFSMAC_LIVE_GVPROXY_RUNNING_OVERRIDE="0"
  export NTFSMAC_LIVE_LOOPBACK_LISTENER_COUNT_OVERRIDE="0"
  export NTFSMAC_LIVE_RESOLVED_IP_OVERRIDE="172.27.1.2"
  export NTFSMAC_LIVE_ROUTE_INTERFACE_OVERRIDE="bridge100"
}

set_nfs_parameters() {
  local mount_point="$1" source="$2" mode="$3"
  export NTFSMAC_LIVE_NFSSTAT_OUTPUT="$mount_point from $source
  -- Current mount parameters:
     NFS parameters: vers=3,tcp,$mode,intr,nolocks"
}

@test "private vmnet soft mount passes without printing identity" {
  export NTFSMAC_LIVE_MOUNT_OUTPUT="disk6s1.local:/mnt/PrivateLabel on /Volumes/PrivateLabel (nfs, nodev, nosuid)"
  set_nfs_parameters "/Volumes/PrivateLabel" "disk6s1.local:/mnt/PrivateLabel" "soft"

  run "$SCRIPT"

  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS — 1 ntfsmac mount(s)"* ]]
  [[ "$output" != *"disk6s1"* ]]
  [[ "$output" != *"PrivateLabel"* ]]
  [[ "$output" != *"172.27.1.2"* ]]
  [[ "$output" != *"bridge100"* ]]
}

@test "loopback endpoint fails closed" {
  export NTFSMAC_LIVE_MOUNT_OUTPUT="disk6s1.local:/mnt/Test on /Volumes/Test (nfs, soft)"
  set_nfs_parameters "/Volumes/Test" "disk6s1.local:/mnt/Test" "soft"
  export NTFSMAC_LIVE_RESOLVED_IP_OVERRIDE="127.0.0.1"

  run "$SCRIPT"

  [ "$status" -ne 0 ]
  [[ "$output" == *"outside the vmnet pool"* ]]
}

@test "hard mount fails the hot-unplug safety gate" {
  export NTFSMAC_LIVE_MOUNT_OUTPUT="disk6s1.local:/mnt/Test on /Volumes/Test (nfs, hard)"
  set_nfs_parameters "/Volumes/Test" "disk6s1.local:/mnt/Test" "hard"

  run "$SCRIPT"

  [ "$status" -ne 0 ]
  [[ "$output" == *"not soft"* ]]
}

@test "soft parameters from an unrelated mount cannot validate a hard ntfsmac mount" {
  export NTFSMAC_LIVE_MOUNT_OUTPUT="disk6s1.local:/mnt/Test on /Volumes/Test (nfs, nodev, nosuid)
nas.example:/share on /Volumes/Share (nfs, nodev, nosuid)"
  export NTFSMAC_LIVE_NFSSTAT_OUTPUT="/Volumes/Test from disk6s1.local:/mnt/Test
  -- Current mount parameters:
     NFS parameters: vers=3,tcp,hard,intr,nolocks
/Volumes/Share from nas.example:/share
  -- Current mount parameters:
     NFS parameters: vers=3,tcp,soft,intr,nolocks"

  run "$SCRIPT"

  [ "$status" -ne 0 ]
  [[ "$output" == *"not soft"* ]]
}

@test "loopback NFS listener fails even when route and endpoint are private" {
  export NTFSMAC_LIVE_MOUNT_OUTPUT="disk6s1.local:/mnt/Test on /Volumes/Test (nfs, soft)"
  set_nfs_parameters "/Volumes/Test" "disk6s1.local:/mnt/Test" "soft"
  export NTFSMAC_LIVE_LOOPBACK_LISTENER_COUNT_OVERRIDE="1"

  run "$SCRIPT"

  [ "$status" -ne 0 ]
  [[ "$output" == *"loopback NFS listener"* ]]
}
