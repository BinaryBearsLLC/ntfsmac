#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SCRIPT="$REPO_ROOT/tests/live/verify-security-transaction.sh"
  STATE_DIR="$BATS_TEST_TMPDIR/security-state"
  mkdir -p "$STATE_DIR"
  cat > "$STATE_DIR/disk2s1.state" <<'STATE'
schema=1
session=disk2s1
endpoint=172.27.1.2
subnet=172.27.1.0/30
interface=bridge100
anchor=com.apple/ntfsmac-disk2s1
pf_token=A1B2C3D4
route_owned=0
private_link=enforced
private_reason=PRIVATE_VMNET_SOFT
vpn_route=notRequired
vpn_route_reason=ROUTE_ALREADY_PRIVATE
pf_policy=enforced
pf_reason=PF_EVALUATED
overall=enforced
overall_reason=SECURITY_ENFORCED
STATE

  export NTFSMAC_LIVE_SECURITY_PLATFORM_OVERRIDE="Darwin"
  export NTFSMAC_LIVE_SECURITY_EUID_OVERRIDE="0"
  export NTFSMAC_LIVE_SECURITY_STATE_DIR="$STATE_DIR"
  export NTFSMAC_LIVE_SECURITY_STATUS_OUTPUT="/dev/disk2s1 on /Volumes/Private (ntfs-3g, soft) VM[cpus: 2, ram: 1024 MiB]"
  export NTFSMAC_LIVE_SECURITY_ROOT_RULES_OUTPUT='anchor "com.apple/*" all'
  export NTFSMAC_LIVE_SECURITY_REFERENCES_OUTPUT='A1B2C3D4 ntfsmac-helper'
  export NTFSMAC_LIVE_SECURITY_ANCHOR_RULES_OUTPUT='pass out quick label ntfsmac-disk2s1-nfs
block drop quick label ntfsmac-disk2s1-egress-block
block drop quick label ntfsmac-disk2s1-ingress-block'
  export NTFSMAC_LIVE_SECURITY_ROUTE_INTERFACE_OVERRIDE='bridge100'
}

@test "fully measured security session passes without leaking identity" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS — 1 session(s)"* ]]
  [[ "$output" != *"disk2s1"* ]]
  [[ "$output" != *"Private"* ]]
  [[ "$output" != *"172.27.1.2"* ]]
  [[ "$output" != *"bridge100"* ]]
  [[ "$output" != *"A1B2C3D4"* ]]
}

@test "missing evaluated wildcard fails even if a child anchor claims success" {
  export NTFSMAC_LIVE_SECURITY_ROOT_RULES_OUTPUT='anchor "unrelated/*" all'
  run "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"evaluated com.apple wildcard anchor is absent"* ]]
}

@test "an active mount without per-session state fails closed" {
  export NTFSMAC_LIVE_SECURITY_STATUS_OUTPUT="/dev/disk2s1 on /Volumes/Private (ntfs-3g, soft) VM[cpus: 2, ram: 1024 MiB]
/dev/disk3s1 on /Volumes/Other (ntfs-3g, soft) VM[cpus: 2, ram: 1024 MiB]"
  run "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"active mount has no security state"* ]]
}

@test "a recorded non-green policy cannot pass the live gate" {
  sed -i '' 's/pf_policy=enforced/pf_policy=notEnforced/' "$STATE_DIR/disk2s1.state"
  sed -i '' 's/overall=enforced/overall=notEnforced/' "$STATE_DIR/disk2s1.state"
  run "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"session is not fully enforced"* ]]
}

@test "an incomplete child anchor cannot pass the live gate" {
  export NTFSMAC_LIVE_SECURITY_ANCHOR_RULES_OUTPUT='pass out quick label ntfsmac-disk2s1-nfs
block drop quick label ntfsmac-disk2s1-egress-block'
  run "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"ingress block policy is not measurably loaded"* ]]
}

@test "an out-of-range vmnet endpoint cannot pass the live gate" {
  sed -i '' 's/endpoint=172.27.1.2/endpoint=172.27.1.999/' "$STATE_DIR/disk2s1.state"
  run "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"endpoint is outside the vmnet pool"* ]]
}
