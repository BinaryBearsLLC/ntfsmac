#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SCRIPT="$REPO_ROOT/cli/lib/pf-teardown.sh"
  STUB_DIR="$(mktemp -d)"
  PFCTL_LOG="$STUB_DIR/pfctl.calls"
  ROUTE_LOG="$STUB_DIR/route.calls"
  export NTFSMAC_SECURITY_STATE_DIR="$STUB_DIR/state"
  export NTFSMAC_PFCTL_BIN="$STUB_DIR/pfctl"
  export NTFSMAC_ROUTE_BIN="$STUB_DIR/route"

  mkdir -p "$NTFSMAC_SECURITY_STATE_DIR"
  cat > "$NTFSMAC_PFCTL_BIN" <<STUB
#!/bin/bash
echo "\$@" >> "$PFCTL_LOG"
exit 0
STUB
  cat > "$NTFSMAC_ROUTE_BIN" <<STUB
#!/bin/bash
echo "\$@" >> "$ROUTE_LOG"
if [[ "\$1 \$2 \$3" == "-n get 172.27.1.2" ]]; then
  echo 'interface: bridge100'
elif [[ "\$1 \$2 \$3" == "-n get 172.27.1.6" ]]; then
  echo 'interface: bridge101'
fi
exit 0
STUB
  chmod +x "$NTFSMAC_PFCTL_BIN" "$NTFSMAC_ROUTE_BIN"
}

teardown() {
  rm -rf "$STUB_DIR"
}

write_state() {
  local session="$1" endpoint="$2" token="$3" route_owned="$4"
  cat > "$NTFSMAC_SECURITY_STATE_DIR/$session.state" <<STATE
schema=1
session=$session
endpoint=$endpoint
anchor=com.apple/ntfsmac-$session
pf_token=$token
route_owned=$route_owned
interface=bridge100
STATE
}

@test "tears down exactly one session anchor token and owned host route" {
  write_state disk2s1 172.27.1.2 A1B2 1
  write_state disk3s1 172.27.1.6 C3D4 1
  run "$SCRIPT" disk2s1
  [ "$status" -eq 0 ]
  [ ! -f "$NTFSMAC_SECURITY_STATE_DIR/disk2s1.state" ]
  [ -f "$NTFSMAC_SECURITY_STATE_DIR/disk3s1.state" ]
  run cat "$PFCTL_LOG"
  [[ "$output" == *"-a com.apple/ntfsmac-disk2s1 -F rules"* ]]
  [[ "$output" == *"-X A1B2"* ]]
  [[ "$output" != *"disk3s1"* ]]
  run cat "$ROUTE_LOG"
  [[ "$output" == *"-n get 172.27.1.2"* ]]
  [[ "$output" == *"delete -host 172.27.1.2"* ]]
}

@test "teardown is idempotent when session state is absent" {
  run "$SCRIPT" disk2s1
  [ "$status" -eq 0 ]
  [[ "$output" == *"notRequired"* ]]
}

@test "no argument reconciles only stale sessions and preserves active protection" {
  write_state disk2s1 172.27.1.2 A1B2 1
  write_state disk3s1 172.27.1.6 C3D4 1
  export NTFSMAC_SECURITY_STATUS_OUTPUT="/dev/disk3s1 on /Volumes/Active (ntfs-3g, soft)"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -f "$NTFSMAC_SECURITY_STATE_DIR/disk2s1.state" ]
  [ -f "$NTFSMAC_SECURITY_STATE_DIR/disk3s1.state" ]
}

@test "--all removes every recorded session without a global PF flush" {
  write_state disk2s1 172.27.1.2 A1B2 1
  write_state disk3s1 172.27.1.6 C3D4 0
  run "$SCRIPT" --all
  [ "$status" -eq 0 ]
  [ ! -f "$NTFSMAC_SECURITY_STATE_DIR/disk2s1.state" ]
  [ ! -f "$NTFSMAC_SECURITY_STATE_DIR/disk3s1.state" ]
  run cat "$PFCTL_LOG"
  [[ "$output" != *"-a com.apple/ntfsmac -F rules"* ]]
  [[ "$output" != $'-F rules\n-F rules'* ]]
}

@test "rejects broad or malformed teardown targets" {
  run "$SCRIPT" "172.27.1.0/30"
  [ "$status" -ne 0 ]
  run "$SCRIPT" "disk2s1; pfctl -d"
  [ "$status" -ne 0 ]
  [ ! -f "$PFCTL_LOG" ]
}
