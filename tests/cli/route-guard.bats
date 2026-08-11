#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  source "$REPO_ROOT/cli/lib/route-guard.sh"
  STUB_DIR="$(mktemp -d)"
  ROUTE_LOG="$STUB_DIR/route.calls"
  ROUTE_GUARD_ROUTE_BIN="$STUB_DIR/route"
  export NTFSMAC_ROUTE_BIN="$ROUTE_GUARD_ROUTE_BIN"
  export NTFSMAC_DEFAULT_INTERFACE_OVERRIDE="utun4"

  cat > "$ROUTE_GUARD_ROUTE_BIN" <<STUB
#!/bin/bash
echo "\$@" >> "$ROUTE_LOG"
exit 0
STUB
  chmod +x "$ROUTE_GUARD_ROUTE_BIN"
}

teardown() {
  rm -rf "$STUB_DIR"
}

@test "an endpoint already routed through the measured bridge needs no owned route" {
  export NTFSMAC_ROUTE_GUARD_INTERFACE_OVERRIDE="bridge100"
  run apply_vpn_bypass "172.27.1.2" "bridge100"
  [ "$status" -eq 0 ]
  [ "$VPN_ROUTE_STATE" = "unknown" ] # bats `run` executes the function in a subshell
  [ ! -f "$ROUTE_LOG" ]
  run "$REPO_ROOT/cli/lib/route-guard.sh" "172.27.1.2" "bridge100"
  [[ "$output" == *"security_vpn_route=notRequired reason=ROUTE_ALREADY_PRIVATE"* ]]
}

@test "a VPN-captured endpoint gets one exact host route and never changes default" {
  export NTFSMAC_ROUTE_GUARD_INTERFACE_OVERRIDE="utun4"
  # The second lookup after add must observe the bridge. The executable stub cannot mutate the
  # exported override, so call the function with a command stub that returns bridge on lookup.
  cat > "$ROUTE_GUARD_ROUTE_BIN" <<STUB
#!/bin/bash
echo "\$@" >> "$ROUTE_LOG"
if [[ "\$1 \$2 \$3" == "-n get 172.27.1.2" ]]; then
  [[ -f "$STUB_DIR/route-added" ]] && echo 'interface: bridge100' || echo 'interface: utun4'
elif [[ "\$1 \$2" == "add -host" ]]; then
  touch "$STUB_DIR/route-added"
fi
exit 0
STUB
  chmod +x "$ROUTE_GUARD_ROUTE_BIN"
  unset NTFSMAC_ROUTE_GUARD_INTERFACE_OVERRIDE

  run "$REPO_ROOT/cli/lib/route-guard.sh" "172.27.1.2" "bridge100"
  [ "$status" -eq 0 ]
  [[ "$output" == *"security_vpn_route=enforced reason=ROUTE_INSTALLED"* ]]
  run cat "$ROUTE_LOG"
  [[ "$output" == *"add -host 172.27.1.2 -interface bridge100"* ]]
  [[ "$output" != *"delete default"* ]]
  [[ "$output" != *"change default"* ]]
}

@test "a split-tunnel endpoint capture is repaired even when the default route is not VPN" {
  export NTFSMAC_DEFAULT_INTERFACE_OVERRIDE="en0"
  cat > "$ROUTE_GUARD_ROUTE_BIN" <<STUB
#!/bin/bash
echo "\$@" >> "$ROUTE_LOG"
if [[ "\$1 \$2 \$3" == "-n get 172.27.1.2" ]]; then
  [[ -f "$STUB_DIR/route-added" ]] && echo 'interface: bridge100' || echo 'interface: utun7'
elif [[ "\$1 \$2" == "add -host" ]]; then
  touch "$STUB_DIR/route-added"
fi
exit 0
STUB
  chmod +x "$ROUTE_GUARD_ROUTE_BIN"
  unset NTFSMAC_ROUTE_GUARD_INTERFACE_OVERRIDE

  run "$REPO_ROOT/cli/lib/route-guard.sh" "172.27.1.2" "bridge100"
  [ "$status" -eq 0 ]
  [[ "$output" == *"security_vpn_route=enforced reason=ROUTE_INSTALLED"* ]]
  run cat "$ROUTE_LOG"
  [[ "$output" == *"add -host 172.27.1.2 -interface bridge100"* ]]
  [[ "$output" != *"default"* ]]
}

@test "a non-private route without a VPN fails visible and changes nothing" {
  export NTFSMAC_ROUTE_GUARD_INTERFACE_OVERRIDE="en0"
  export NTFSMAC_DEFAULT_INTERFACE_OVERRIDE="en0"
  run "$REPO_ROOT/cli/lib/route-guard.sh" "172.27.1.2" "bridge100"
  [ "$status" -ne 0 ]
  [[ "$output" == *"reason=ROUTE_NOT_PRIVATE"* ]]
  [ ! -f "$ROUTE_LOG" ]
}

@test "rejects endpoint and interface injection before invoking route" {
  run "$REPO_ROOT/cli/lib/route-guard.sh" "172.27.1.2; route delete default" "bridge100"
  [ "$status" -ne 0 ]
  run "$REPO_ROOT/cli/lib/route-guard.sh" "172.27.1.2" "bridge100; touch /tmp/x"
  [ "$status" -ne 0 ]
  [ ! -f "$ROUTE_LOG" ]
}

@test "teardown leaves a replacement route on another interface untouched" {
  cat > "$ROUTE_GUARD_ROUTE_BIN" <<STUB
#!/bin/bash
echo "\$@" >> "$ROUTE_LOG"
if [[ "\$1 \$2 \$3" == "-n get 172.27.1.2" ]]; then
  echo 'interface: utun9'
fi
exit 0
STUB
  chmod +x "$ROUTE_GUARD_ROUTE_BIN"

  run remove_vpn_bypass "172.27.1.2" "bridge100"
  [ "$status" -eq 0 ]
  run cat "$ROUTE_LOG"
  [[ "$output" == *"-n get 172.27.1.2"* ]]
  [[ "$output" != *"delete -host"* ]]
}
