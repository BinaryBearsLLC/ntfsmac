#!/bin/bash
# Read-only packaged-app gate for per-session PF/route hardening. Output is count + fixed tokens;
# no device, label, path, address, interface, PID, VPN provider, or PF token is emitted.
set -euo pipefail

STATE_DIR="${NTFSMAC_LIVE_SECURITY_STATE_DIR:-/var/run/ntfsmac/security}"
PFCTL_BIN="${NTFSMAC_LIVE_SECURITY_PFCTL_BIN:-/sbin/pfctl}"
ROUTE_BIN="${NTFSMAC_LIVE_SECURITY_ROUTE_BIN:-/sbin/route}"
ANYLINUXFS_BIN="${NTFSMAC_LIVE_SECURITY_ANYLINUXFS_BIN:-/usr/local/ntfsmac/bin/anylinuxfs}"

fail() {
  printf 'verify-security-transaction: FAIL — %s\n' "$1" >&2
  exit 1
}

state_value() {
  local file="$1" key="$2"
  awk -F= -v wanted="$key" '$1 == wanted { print substr($0, length($1) + 2); exit }' "$file"
}

valid_vmnet_endpoint() {
  local endpoint="$1" a b c d
  [[ "$endpoint" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] || return 1
  IFS=. read -r a b c d <<< "$endpoint"
  a=$((10#$a)); b=$((10#$b)); c=$((10#$c)); d=$((10#$d))
  [[ "$a" -eq 172 && "$b" -ge 16 && "$b" -le 31 && "$c" -le 255 && "$d" -le 255 ]]
}

[[ "${NTFSMAC_LIVE_SECURITY_PLATFORM_OVERRIDE-$(uname -s)}" == "Darwin" ]] \
  || fail "macOS is required"
[[ "${NTFSMAC_LIVE_SECURITY_EUID_OVERRIDE-${EUID}}" == "0" ]] \
  || fail "run with sudo so PF state can be inspected"
[[ -d "$STATE_DIR" && ! -L "$STATE_DIR" ]] || fail "session state directory is unavailable"

status_output="${NTFSMAC_LIVE_SECURITY_STATUS_OUTPUT-}"
if [[ -z "$status_output" ]]; then
  [[ -x "$ANYLINUXFS_BIN" ]] || fail "anylinuxfs status source is unavailable"
  status_output="$("$ANYLINUXFS_BIN" status 2>/dev/null)" || fail "anylinuxfs status failed"
fi
[[ -n "$status_output" ]] || fail "no active anylinuxfs sessions"

root_rules="${NTFSMAC_LIVE_SECURITY_ROOT_RULES_OUTPUT-}"
if [[ -z "$root_rules" ]]; then
  root_rules="$("$PFCTL_BIN" -sr 2>/dev/null)" || fail "PF root rules cannot be inspected"
fi
grep -F 'anchor "com.apple/*"' <<< "$root_rules" >/dev/null 2>&1 \
  || fail "the evaluated com.apple wildcard anchor is absent"

references="${NTFSMAC_LIVE_SECURITY_REFERENCES_OUTPUT-}"
if [[ -z "$references" ]]; then
  references="$("$PFCTL_BIN" -s References 2>/dev/null)" \
    || fail "PF enable references cannot be inspected"
fi

checked=0
for state_file in "$STATE_DIR"/*.state; do
  [[ -e "$state_file" ]] || continue
  [[ -f "$state_file" && ! -L "$state_file" ]] || fail "a session state entry is not a regular file"
  session="$(basename "$state_file" .state)"
  [[ "$session" =~ ^disk[0-9]+s[0-9]+$ ]] || fail "a session identifier is malformed"
  grep -F "/dev/$session on " <<< "$status_output" >/dev/null 2>&1 \
    || fail "a stale security session is present"

  anchor="$(state_value "$state_file" anchor)"
  token="$(state_value "$state_file" pf_token)"
  endpoint="$(state_value "$state_file" endpoint)"
  interface="$(state_value "$state_file" interface)"
  private_state="$(state_value "$state_file" private_link)"
  route_state="$(state_value "$state_file" vpn_route)"
  pf_state="$(state_value "$state_file" pf_policy)"
  overall="$(state_value "$state_file" overall)"

  [[ "$(state_value "$state_file" schema)" == "1" ]] || fail "a session schema is unsupported"
  [[ "$(state_value "$state_file" session)" == "$session" ]] || fail "a session owner is inconsistent"
  [[ "$anchor" == "com.apple/ntfsmac-$session" ]] || fail "an anchor owner is malformed"
  [[ "$token" =~ ^[[:xdigit:]]+$ ]] || fail "a PF enable token is missing"
  valid_vmnet_endpoint "$endpoint" || fail "a session endpoint is outside the vmnet pool"
  [[ "$interface" =~ ^bridge[0-9]+$ ]] || fail "a session interface is not a bridge"
  [[ "$private_state" == "enforced" && "$pf_state" == "enforced" && "$overall" == "enforced" ]] \
    || fail "a session is not fully enforced"
  [[ "$route_state" == "enforced" || "$route_state" == "notRequired" ]] \
    || fail "a session route is not proven safe"
  grep -F "$token" <<< "$references" >/dev/null 2>&1 || fail "a PF enable reference is missing"

  anchor_rules="${NTFSMAC_LIVE_SECURITY_ANCHOR_RULES_OUTPUT-}"
  if [[ -z "$anchor_rules" ]]; then
    anchor_rules="$("$PFCTL_BIN" -a "$anchor" -sr 2>/dev/null)" \
      || fail "a session anchor cannot be inspected"
  fi
  grep -Eq "label[[:space:]]+\\\"?ntfsmac-${session}-nfs\\\"?([[:space:]]|$)" <<< "$anchor_rules" \
    || fail "a session NFS allow policy is not measurably loaded"
  grep -Eq "label[[:space:]]+\\\"?ntfsmac-${session}-egress-block\\\"?([[:space:]]|$)" <<< "$anchor_rules" \
    || fail "a session egress block policy is not measurably loaded"
  grep -Eq "label[[:space:]]+\\\"?ntfsmac-${session}-ingress-block\\\"?([[:space:]]|$)" <<< "$anchor_rules" \
    || fail "a session ingress block policy is not measurably loaded"

  route_interface="${NTFSMAC_LIVE_SECURITY_ROUTE_INTERFACE_OVERRIDE-}"
  if [[ -z "$route_interface" ]]; then
    route_interface="$("$ROUTE_BIN" -n get "$endpoint" 2>/dev/null \
      | awk '/interface:/{print $2; exit}')"
  fi
  [[ "$route_interface" == "$interface" ]] || fail "a session route left its measured bridge"
  checked=$((checked + 1))
done

[[ "$checked" -gt 0 ]] || fail "no security session state was found"

# Every active device-shaped anylinuxfs status row must have a corresponding state file.
active_count=0
while IFS= read -r line; do
  [[ "$line" == /dev/disk*s*" on "* ]] || continue
  session="${line%% on *}"
  session="${session#/dev/}"
  [[ "$session" =~ ^disk[0-9]+s[0-9]+$ ]] || continue
  [[ -f "$STATE_DIR/$session.state" && ! -L "$STATE_DIR/$session.state" ]] \
    || fail "an active mount has no security state"
  active_count=$((active_count + 1))
done <<< "$status_output"
[[ "$active_count" -eq "$checked" ]] || fail "active and protected session counts differ"

printf 'verify-security-transaction: PASS — %s session(s), evaluated PF, private route, owned teardown state\n' "$checked"
