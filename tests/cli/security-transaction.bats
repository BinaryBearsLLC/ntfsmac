#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SCRIPT="$REPO_ROOT/cli/lib/security-transaction.sh"
  STUB_DIR="$(mktemp -d)"
  export NTFSMAC_SECURITY_STATE_DIR="$STUB_DIR/state"
  export NTFSMAC_PFCTL_BIN="$STUB_DIR/pfctl"
  export NTFSMAC_ROUTE_BIN="$STUB_DIR/route"
  export NTFSMAC_SECURITY_STATUS_OUTPUT="/dev/disk2s1 on /Volumes/Test (ntfs-3g, soft, mounted by test) VM[cpus: 2, ram: 1024 MiB]"
  export NTFSMAC_SECURITY_MOUNT_OUTPUT="disk2s1.local:/mnt/Test on /Volumes/Test (nfs, nodev, nosuid)"
  export NTFSMAC_SECURITY_NFSSTAT_OUTPUT="/Volumes/Test from disk2s1.local:/mnt/Test
  -- Current mount parameters:
     NFS parameters: vers=3,tcp,soft,intr,nolocks,port=2049,mountport=32767"
  export NTFSMAC_SECURITY_RESOLVED_IP_OVERRIDE="172.27.1.2"
  export NTFSMAC_SECURITY_ROUTE_INTERFACE_OVERRIDE="bridge100"
  export NTFSMAC_ROUTE_GUARD_INTERFACE_OVERRIDE="bridge100"
  export NTFSMAC_DEFAULT_INTERFACE_OVERRIDE="utun4"
  export PFCTL_LOG="$STUB_DIR/pfctl.calls"

  cat > "$NTFSMAC_PFCTL_BIN" <<'STUB'
#!/bin/bash
echo "$@" >> "$PFCTL_LOG"
if [[ "$*" == "-sr" ]]; then
  echo 'anchor "com.apple/*" all'
elif [[ "$*" == "-E" ]]; then
  echo 'pf enabled'
  echo 'Token : A1B2C3D4'
elif [[ "$1" == "-a" && "$3" == "-sr" ]]; then
  session="${2##*-}"
  echo "pass out quick label ntfsmac-${session}-nfs"
  echo "block drop quick label ntfsmac-${session}-egress-block"
  echo "block drop quick label ntfsmac-${session}-ingress-block"
fi
exit 0
STUB
  cat > "$NTFSMAC_ROUTE_BIN" <<'STUB'
#!/bin/bash
exit 0
STUB
  chmod +x "$NTFSMAC_PFCTL_BIN" "$NTFSMAC_ROUTE_BIN"
}

teardown() {
  rm -rf "$STUB_DIR"
}

@test "a measured vmnet soft mount gets an evaluated per-session PF policy" {
  run bash -c "source '$SCRIPT'; security_apply_for_mount disk2s1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"security_private_link=enforced reason=PRIVATE_VMNET_SOFT"* ]]
  [[ "$output" == *"security_vpn_route=notRequired reason=ROUTE_ALREADY_PRIVATE"* ]]
  [[ "$output" == *"security_pf_policy=enforced reason=PF_EVALUATED"* ]]
  [[ "$output" == *"security_overall=enforced reason=SECURITY_ENFORCED"* ]]
  [ -f "$NTFSMAC_SECURITY_STATE_DIR/disk2s1.state" ]
  run grep -F "anchor=com.apple/ntfsmac-disk2s1" "$NTFSMAC_SECURITY_STATE_DIR/disk2s1.state"
  [ "$status" -eq 0 ]
  run grep -F "pf_token=A1B2C3D4" "$NTFSMAC_SECURITY_STATE_DIR/disk2s1.state"
  [ "$status" -eq 0 ]
}

@test "a failed backend releases PF acquired during pre-mount transport preparation" {
  export NTFSMAC_SECURITY_BRIDGE_CANDIDATES_FILE="$STUB_DIR/bridge-candidates"
  run bash -c "
    source '$SCRIPT'
    security_begin_prepared_mount disk2s1
    printf 'bridge100|172.27.1.2|172.27.1.0/30\\n' > '$NTFSMAC_SECURITY_BRIDGE_CANDIDATES_FILE'
    sleep 2 & mount_pid=\$!
    security_prepare_mount_transport disk2s1 \"\$mount_pid\"
    security_abort_prepared_mount disk2s1
    kill \"\$mount_pid\" 2>/dev/null || true
    wait \"\$mount_pid\" 2>/dev/null || true
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"security_prepare=enforced reason=PREMOUNT_TRANSPORT_MEASURED"* ]]
  [[ "$output" == *"security_prepare_cleanup=enforced reason=PREMOUNT_RESOURCES_RELEASED"* ]]
  [ ! -e "$NTFSMAC_SECURITY_STATE_DIR/disk2s1.state" ]
  run cat "$PFCTL_LOG"
  [[ "$output" == *"-a com.apple/ntfsmac-disk2s1 -F rules"* ]]
  [[ "$output" == *"-X A1B2C3D4"* ]]
}

@test "private bridge discovery comes from the endpoint's exact vmnet /30" {
  unset NTFSMAC_SECURITY_ROUTE_INTERFACE_OVERRIDE
  unset NTFSMAC_SECURITY_BRIDGE_INTERFACE_OVERRIDE
  export NTFSMAC_IFCONFIG_BIN="$STUB_DIR/ifconfig"
  cat > "$NTFSMAC_IFCONFIG_BIN" <<'STUB'
#!/bin/bash
echo 'bridge99: flags=0<>'
echo '        inet 172.27.9.1 netmask 0xfffffffc'
echo 'bridge100: flags=0<>'
echo '        inet 172.27.1.1 netmask 0xfffffffc'
STUB
  chmod +x "$NTFSMAC_IFCONFIG_BIN"

  run bash -c "source '$SCRIPT'; security_apply_for_mount disk2s1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"security_private_link=enforced reason=PRIVATE_VMNET_SOFT"* ]]
  run grep -F 'interface=bridge100' "$NTFSMAC_SECURITY_STATE_DIR/disk2s1.state"
  [ "$status" -eq 0 ]
}

@test "bridge discovery rejects a matching address without an exact /30 netmask" {
  unset NTFSMAC_SECURITY_ROUTE_INTERFACE_OVERRIDE
  unset NTFSMAC_SECURITY_BRIDGE_INTERFACE_OVERRIDE
  export NTFSMAC_IFCONFIG_BIN="$STUB_DIR/ifconfig"
  cat > "$NTFSMAC_IFCONFIG_BIN" <<'STUB'
#!/bin/bash
echo 'bridge100: flags=0<>'
echo '        inet 172.27.1.1 netmask 0xffffff00'
STUB
  chmod +x "$NTFSMAC_IFCONFIG_BIN"

  run bash -c "source '$SCRIPT'; security_apply_for_mount disk2s1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"security_private_link=notEnforced reason=BRIDGE_NOT_FOUND"* ]]
  [[ "$output" == *"security_pf_policy=notEnforced reason=PF_SKIPPED_UNSAFE_MOUNT"* ]]
  [ ! -f "$PFCTL_LOG" ]
}

@test "state writer refuses a symlinked runtime directory" {
  mkdir -p "$STUB_DIR/redirected-state"
  ln -s "$STUB_DIR/redirected-state" "$NTFSMAC_SECURITY_STATE_DIR"

  run bash -c "source '$SCRIPT'; security_apply_for_mount disk2s1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"security_overall=notEnforced reason=STATE_WRITE_FAILED"* ]]
  [ ! -f "$STUB_DIR/redirected-state/disk2s1.state" ]
}

@test "reconciliation refuses a symlinked runtime directory without touching its target" {
  mkdir -p "$STUB_DIR/redirected-state"
  printf 'sentinel\n' > "$STUB_DIR/redirected-state/disk2s1.state"
  ln -s "$STUB_DIR/redirected-state" "$NTFSMAC_SECURITY_STATE_DIR"

  run bash -c "source '$SCRIPT'; security_reconcile"
  [ "$status" -eq 0 ]
  [[ "$output" == *"security_reconcile=unknown reason=STATE_DIR_UNSAFE"* ]]
  [ -f "$STUB_DIR/redirected-state/disk2s1.state" ]
  [ ! -f "$PFCTL_LOG" ]
}

@test "an empty runtime directory needs no status probe" {
  mkdir -p "$NTFSMAC_SECURITY_STATE_DIR"
  unset NTFSMAC_SECURITY_STATUS_OUTPUT
  export NTFSMAC_ANYLINUXFS_BIN="$STUB_DIR/wedged-anylinuxfs"
  cat > "$NTFSMAC_ANYLINUXFS_BIN" <<'STUB'
#!/bin/bash
exec sleep 30
STUB
  chmod +x "$NTFSMAC_ANYLINUXFS_BIN"

  run bash -c "source '$SCRIPT'; security_reconcile"
  [ "$status" -eq 0 ]
  [[ "$output" == *"security_reconcile=notRequired reason=NO_SESSION_STATE"* ]]
}

@test "a malformed state filename cannot be silently abandoned" {
  mkdir -p "$NTFSMAC_SECURITY_STATE_DIR"
  printf 'schema=1\n' > "$NTFSMAC_SECURITY_STATE_DIR/not-a-device.state"

  run bash -c "source '$SCRIPT'; security_reconcile"
  [ "$status" -ne 0 ]
  [[ "$output" == *"security_reconcile=notEnforced reason=STALE_TEARDOWN_INCOMPLETE"* ]]
  [ -f "$NTFSMAC_SECURITY_STATE_DIR/not-a-device.state" ]
}

@test "PF readback must contain the allow rule and both block rules" {
  cat > "$NTFSMAC_PFCTL_BIN" <<'STUB'
#!/bin/bash
echo "$@" >> "$PFCTL_LOG"
if [[ "$*" == "-sr" ]]; then
  echo 'anchor "com.apple/*" all'
elif [[ "$*" == "-E" ]]; then
  echo 'Token : A1B2C3D4'
elif [[ "$1" == "-a" && "$3" == "-sr" ]]; then
  echo 'pass out quick label ntfsmac-disk2s1-nfs'
  echo 'block drop quick label ntfsmac-disk2s1-egress-block'
fi
exit 0
STUB
  chmod +x "$NTFSMAC_PFCTL_BIN"

  run bash -c "source '$SCRIPT'; security_apply_for_mount disk2s1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"security_pf_policy=notEnforced reason=PF_MEASUREMENT_FAILED"* ]]
  [[ "$output" == *"security_overall=notEnforced reason=SECURITY_INCOMPLETE"* ]]
}

@test "failed cleanup after PF readback keeps the enable token for retry" {
  cat > "$NTFSMAC_PFCTL_BIN" <<'STUB'
#!/bin/bash
if [[ "$*" == "-sr" ]]; then
  echo 'anchor "com.apple/*" all'
elif [[ "$*" == "-E" ]]; then
  echo 'Token : A1B2C3D4'
elif [[ "$1" == "-a" && "$3" == "-sr" ]]; then
  echo 'pass out quick label ntfsmac-disk2s1-nfs'
  echo 'block drop quick label ntfsmac-disk2s1-egress-block'
elif [[ "$1" == "-X" ]]; then
  exit 1
fi
exit 0
STUB
  chmod +x "$NTFSMAC_PFCTL_BIN"

  run bash -c "source '$SCRIPT'; security_apply_for_mount disk2s1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"security_pf_policy=notEnforced reason=PF_MEASUREMENT_FAILED_CLEANUP_PENDING"* ]]
  run grep -F 'pf_token=A1B2C3D4' "$NTFSMAC_SECURITY_STATE_DIR/disk2s1.state"
  [ "$status" -eq 0 ]
}

@test "an unparseable PF enable token is never forgotten as successful cleanup" {
  cat > "$NTFSMAC_PFCTL_BIN" <<'STUB'
#!/bin/bash
echo "$@" >> "$PFCTL_LOG"
if [[ "$*" == "-sr" ]]; then
  echo 'anchor "com.apple/*" all'
elif [[ "$*" == "-E" ]]; then
  echo 'pf enabled without an ownership token'
fi
exit 0
STUB
  chmod +x "$NTFSMAC_PFCTL_BIN"

  run bash -c "source '$SCRIPT'; security_apply_for_mount disk2s1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"security_pf_policy=notEnforced reason=PF_ENABLE_TOKEN_MISSING_CLEANUP_PENDING"* ]]
  run grep -F 'pf_token=unavailable' "$NTFSMAC_SECURITY_STATE_DIR/disk2s1.state"
  [ "$status" -eq 0 ]

  run bash -c "source '$SCRIPT'; security_teardown_session disk2s1"
  [ "$status" -ne 0 ]
  [[ "$output" == *"security_teardown=notEnforced reason=TEARDOWN_INCOMPLETE"* ]]
  [ -f "$NTFSMAC_SECURITY_STATE_DIR/disk2s1.state" ]
  run cat "$PFCTL_LOG"
  [[ "$output" == *"-a com.apple/ntfsmac-disk2s1 -F rules"* ]]
  [[ "$output" != *"-X unavailable"* ]]
}

@test "session teardown and teardown-all refuse an unsafe state entry" {
  mkdir -p "$NTFSMAC_SECURITY_STATE_DIR"
  printf 'do not touch\n' > "$STUB_DIR/state-target"
  ln -s "$STUB_DIR/state-target" "$NTFSMAC_SECURITY_STATE_DIR/disk2s1.state"

  run bash -c "source '$SCRIPT'; security_teardown_session disk2s1"
  [ "$status" -ne 0 ]
  [[ "$output" == *"security_teardown=notEnforced reason=STATE_ENTRY_UNSAFE"* ]]
  [ -L "$NTFSMAC_SECURITY_STATE_DIR/disk2s1.state" ]
  run cat "$STUB_DIR/state-target"
  [ "$output" = "do not touch" ]

  run bash -c "source '$SCRIPT'; security_teardown_all"
  [ "$status" -ne 0 ]
  [[ "$output" == *"security_teardown=notEnforced reason=ALL_TEARDOWN_INCOMPLETE"* ]]
  [ -L "$NTFSMAC_SECURITY_STATE_DIR/disk2s1.state" ]
}

@test "an unevaluated PF path stays visible non-green and is never loaded" {
  cat > "$NTFSMAC_PFCTL_BIN" <<'STUB'
#!/bin/bash
echo "$@" >> "$PFCTL_LOG"
[[ "$*" == "-sr" ]] && echo 'anchor "unrelated/*" all'
exit 0
STUB
  chmod +x "$NTFSMAC_PFCTL_BIN"

  run bash -c "source '$SCRIPT'; security_apply_for_mount disk2s1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"security_pf_policy=notEnforced reason=PF_EVALUATED_PATH_MISSING"* ]]
  [[ "$output" == *"security_overall=notEnforced reason=SECURITY_INCOMPLETE"* ]]
  run cat "$PFCTL_LOG"
  [[ "$output" == "-sr" ]]
}

@test "a VPN-captured endpoint records and later removes only its owned host route" {
  unset NTFSMAC_SECURITY_ROUTE_INTERFACE_OVERRIDE
  export NTFSMAC_SECURITY_BRIDGE_INTERFACE_OVERRIDE="bridge100"
  unset NTFSMAC_ROUTE_GUARD_INTERFACE_OVERRIDE
  cat > "$NTFSMAC_ROUTE_BIN" <<STUB
#!/bin/bash
echo "\$@" >> "$STUB_DIR/route.calls"
if [[ "\$1 \$2 \$3" == "-n get 172.27.1.2" ]]; then
  [[ -f "$STUB_DIR/route-added" ]] && echo 'interface: bridge100' || echo 'interface: utun4'
elif [[ "\$1 \$2" == "add -host" ]]; then
  touch "$STUB_DIR/route-added"
elif [[ "\$1 \$2" == "delete -host" ]]; then
  rm -f "$STUB_DIR/route-added"
fi
exit 0
STUB
  chmod +x "$NTFSMAC_ROUTE_BIN"

  run bash -c "source '$SCRIPT'; security_apply_for_mount disk2s1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"security_vpn_route=enforced reason=ROUTE_INSTALLED"* ]]
  run grep -F "route_owned=1" "$NTFSMAC_SECURITY_STATE_DIR/disk2s1.state"
  [ "$status" -eq 0 ]

  run bash -c "source '$SCRIPT'; security_teardown_session disk2s1"
  [ "$status" -eq 0 ]
  run cat "$STUB_DIR/route.calls"
  [[ "$output" == *"add -host 172.27.1.2 -interface bridge100"* ]]
  [[ "$output" == *"delete -host 172.27.1.2"* ]]
  [[ "$output" != *"default"* ]]
}

@test "a hard or unmeasurable NFS mount never loads PF and cannot turn green" {
  export NTFSMAC_SECURITY_NFSSTAT_OUTPUT="/Volumes/Test from disk2s1.local:/mnt/Test
  -- Current mount parameters:
     NFS parameters: vers=3,tcp,hard,intr,nolocks"
  run bash -c "source '$SCRIPT'; security_apply_for_mount disk2s1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"security_private_link=notEnforced reason=NFS_SOFT_UNPROVEN"* ]]
  [[ "$output" == *"security_pf_policy=notEnforced reason=PF_SKIPPED_UNSAFE_MOUNT"* ]]
  [ ! -f "$PFCTL_LOG" ]
}

@test "concurrent mounts retain independent anchors tokens and teardown" {
  run bash -c "source '$SCRIPT'; security_apply_for_mount disk2s1"
  [ "$status" -eq 0 ]

  export NTFSMAC_SECURITY_STATUS_OUTPUT="/dev/disk3s1 on /Volumes/Other (ntfs-3g, soft, mounted by test) VM[cpus: 2, ram: 1024 MiB]"
  export NTFSMAC_SECURITY_MOUNT_OUTPUT="disk3s1.local:/mnt/Other on /Volumes/Other (nfs, nodev, nosuid)"
  export NTFSMAC_SECURITY_NFSSTAT_OUTPUT="/Volumes/Other from disk3s1.local:/mnt/Other
  -- Current mount parameters:
     NFS parameters: vers=3,tcp,soft,intr,nolocks"
  export NTFSMAC_SECURITY_RESOLVED_IP_OVERRIDE="172.27.1.6"
  run bash -c "source '$SCRIPT'; security_apply_for_mount disk3s1"
  [ "$status" -eq 0 ]
  [ -f "$NTFSMAC_SECURITY_STATE_DIR/disk2s1.state" ]
  [ -f "$NTFSMAC_SECURITY_STATE_DIR/disk3s1.state" ]

  run bash -c "source '$SCRIPT'; security_teardown_session disk2s1"
  [ "$status" -eq 0 ]
  [ ! -f "$NTFSMAC_SECURITY_STATE_DIR/disk2s1.state" ]
  [ -f "$NTFSMAC_SECURITY_STATE_DIR/disk3s1.state" ]
  run cat "$PFCTL_LOG"
  [[ "$output" == *"-a com.apple/ntfsmac-disk2s1 -F rules"* ]]
  [[ "$output" != *"-a com.apple/ntfsmac-disk3s1 -F rules"* ]]
}

@test "failed PF token release preserves session state for a safe retry" {
  run bash -c "source '$SCRIPT'; security_apply_for_mount disk2s1"
  [ "$status" -eq 0 ]
  [ -f "$NTFSMAC_SECURITY_STATE_DIR/disk2s1.state" ]

  cat > "$NTFSMAC_PFCTL_BIN" <<'STUB'
#!/bin/bash
[[ "$1" == "-X" ]] && exit 1
exit 0
STUB
  chmod +x "$NTFSMAC_PFCTL_BIN"

  run bash -c "source '$SCRIPT'; security_teardown_session disk2s1"
  [ "$status" -ne 0 ]
  [[ "$output" == *"security_teardown=notEnforced reason=TEARDOWN_INCOMPLETE"* ]]
  [ -f "$NTFSMAC_SECURITY_STATE_DIR/disk2s1.state" ]
}

@test "status-source failure preserves every existing protection during reconciliation" {
  mkdir -p "$NTFSMAC_SECURITY_STATE_DIR"
  printf 'schema=1\nsession=disk2s1\nanchor=com.apple/ntfsmac-disk2s1\npf_token=A1B2\nroute_owned=0\n' \
    > "$NTFSMAC_SECURITY_STATE_DIR/disk2s1.state"
  unset NTFSMAC_SECURITY_STATUS_OUTPUT
  export NTFSMAC_ANYLINUXFS_BIN="$STUB_DIR/missing-anylinuxfs"

  run bash -c "source '$SCRIPT'; security_reconcile"
  [ "$status" -eq 0 ]
  [[ "$output" == *"security_reconcile=unknown reason=STATUS_UNAVAILABLE"* ]]
  [ -f "$NTFSMAC_SECURITY_STATE_DIR/disk2s1.state" ]
  [ ! -f "$PFCTL_LOG" ]
}

@test "a wedged status source is bounded and preserves existing protection" {
  mkdir -p "$NTFSMAC_SECURITY_STATE_DIR"
  printf 'schema=1\nsession=disk2s1\nanchor=com.apple/ntfsmac-disk2s1\npf_token=A1B2\nroute_owned=0\n' \
    > "$NTFSMAC_SECURITY_STATE_DIR/disk2s1.state"
  unset NTFSMAC_SECURITY_STATUS_OUTPUT
  export NTFSMAC_SECURITY_STATUS_TIMEOUT=1
  export NTFSMAC_ANYLINUXFS_BIN="$STUB_DIR/wedged-anylinuxfs"
  cat > "$NTFSMAC_ANYLINUXFS_BIN" <<'STUB'
#!/bin/bash
exec sleep 30
STUB
  chmod +x "$NTFSMAC_ANYLINUXFS_BIN"

  run bash -c "source '$SCRIPT'; security_reconcile"
  [ "$status" -eq 0 ]
  [[ "$output" == *"security_reconcile=unknown reason=STATUS_UNAVAILABLE"* ]]
  [ -f "$NTFSMAC_SECURITY_STATE_DIR/disk2s1.state" ]
  [ ! -f "$PFCTL_LOG" ]
}

@test "shell mount and unmount entrypoints own the transaction boundary" {
  run grep -F 'security_apply_for_mount "$device"' "$REPO_ROOT/cli/commands/mount.sh"
  [ "$status" -eq 0 ]
  run grep -F 'security_teardown_session "$security_session"' "$REPO_ROOT/cli/commands/unmount.sh"
  [ "$status" -eq 0 ]
}
