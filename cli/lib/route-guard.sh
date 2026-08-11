#!/bin/bash
# cli/lib/route-guard.sh — 1-vpn-bypass (PLAN.md §6; Phase 1 defense-in-depth).
#
# Measures the route to one vmnet guest endpoint. If a full- or split-tunnel VPN route has
# captured that endpoint, adds an exact host route through the measured bridge. A route that already resolves
# through the bridge is `notRequired`; unrelated/default VPN routes are never modified.
set -u

# Output variables are intentionally fixed-token state for security-transaction.sh.
# These globals are the sourced-library result contract consumed after apply_vpn_bypass returns.
# shellcheck disable=SC2034
VPN_ROUTE_STATE="unknown"
VPN_ROUTE_REASON="ROUTE_UNMEASURED"
VPN_ROUTE_OWNED="0"

ROUTE_GUARD_ROUTE_BIN="${NTFSMAC_ROUTE_BIN:-/sbin/route}"

route_guard_valid_endpoint() {
  local endpoint="${1:-}" a b c d
  [[ "$endpoint" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] || return 1
  IFS=. read -r a b c d <<< "$endpoint"
  a=$((10#$a)); b=$((10#$b)); c=$((10#$c)); d=$((10#$d))
  [[ "$a" -eq 172 && "$b" -ge 16 && "$b" -le 31 && "$c" -le 255 && "$d" -le 255 ]]
}

route_guard_interface_for() {
  local endpoint="$1" interface
  interface="${NTFSMAC_ROUTE_GUARD_INTERFACE_OVERRIDE-}"
  if [[ -z "$interface" ]]; then
    interface="$("$ROUTE_GUARD_ROUTE_BIN" -n get "$endpoint" 2>/dev/null \
      | awk '/interface:/{print $2; exit}')"
  fi
  printf '%s\n' "$interface"
}

route_guard_default_interface() {
  local interface
  interface="${NTFSMAC_DEFAULT_INTERFACE_OVERRIDE-}"
  if [[ -z "$interface" ]]; then
    interface="$("$ROUTE_GUARD_ROUTE_BIN" -n get default 2>/dev/null \
      | awk '/interface:/{print $2; exit}')"
  fi
  printf '%s\n' "$interface"
}

# apply_vpn_bypass <vm-endpoint-ip> <bridge-interface>
apply_vpn_bypass() {
  local endpoint="${1:-}" bridge_iface="${2:-}" current_iface default_iface

  VPN_ROUTE_STATE="unknown"
  VPN_ROUTE_REASON="ROUTE_UNMEASURED"
  VPN_ROUTE_OWNED="0"

  if ! route_guard_valid_endpoint "$endpoint" || [[ ! "$bridge_iface" =~ ^bridge[0-9]+$ ]]; then
    VPN_ROUTE_STATE="notEnforced"
    VPN_ROUTE_REASON="ROUTE_INPUT_INVALID"
    echo "route-guard: a vmnet endpoint and bridge interface are required" >&2
    return 1
  fi

  current_iface="$(route_guard_interface_for "$endpoint")"
  if [[ "$current_iface" == "$bridge_iface" ]]; then
    VPN_ROUTE_STATE="notRequired"
    VPN_ROUTE_REASON="ROUTE_ALREADY_PRIVATE"
    return 0
  fi

  default_iface="$(route_guard_default_interface)"
  if [[ ! "$current_iface" =~ ^(utun|ppp|tun)[0-9]*$ \
    && ! "$default_iface" =~ ^(utun|ppp|tun)[0-9]*$ ]]; then
    VPN_ROUTE_STATE="notEnforced"
    VPN_ROUTE_REASON="ROUTE_NOT_PRIVATE"
    return 1
  fi

  if ! "$ROUTE_GUARD_ROUTE_BIN" add -host "$endpoint" -interface "$bridge_iface" >/dev/null 2>&1; then
    VPN_ROUTE_STATE="notEnforced"
    VPN_ROUTE_REASON="ROUTE_ADD_FAILED"
    return 1
  fi
  VPN_ROUTE_OWNED="1"

  current_iface="$(route_guard_interface_for "$endpoint")"
  if [[ "$current_iface" != "$bridge_iface" ]]; then
    "$ROUTE_GUARD_ROUTE_BIN" delete -host "$endpoint" >/dev/null 2>&1 || true
    # shellcheck disable=SC2034
    VPN_ROUTE_OWNED="0"
    VPN_ROUTE_STATE="notEnforced"
    VPN_ROUTE_REASON="ROUTE_MEASUREMENT_FAILED"
    return 1
  fi

  VPN_ROUTE_STATE="enforced"
  VPN_ROUTE_REASON="ROUTE_INSTALLED"
  return 0
}

remove_vpn_bypass() {
  local endpoint="${1:-}" bridge_iface="${2:-}" current_iface
  route_guard_valid_endpoint "$endpoint" || return 1
  [[ "$bridge_iface" =~ ^bridge[0-9]+$ ]] || return 1
  current_iface="$(route_guard_interface_for "$endpoint")"
  [[ -n "$current_iface" ]] || return 1
  # The recorded route may have been replaced externally. Only delete when the live route still
  # resolves through the exact bridge this session owned; a different interface proves our route
  # is already absent and must not be disturbed.
  [[ "$current_iface" == "$bridge_iface" ]] || return 0
  if "$ROUTE_GUARD_ROUTE_BIN" delete -host "$endpoint" >/dev/null 2>&1; then
    return 0
  fi
  # Deletion is idempotent only when a fresh lookup proves the owned bridge route disappeared.
  current_iface="$(route_guard_interface_for "$endpoint")"
  [[ -n "$current_iface" && "$current_iface" != "$bridge_iface" ]]
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if apply_vpn_bypass "$@"; then
    printf 'security_vpn_route=%s reason=%s\n' "$VPN_ROUTE_STATE" "$VPN_ROUTE_REASON"
  else
    printf 'security_vpn_route=%s reason=%s\n' "$VPN_ROUTE_STATE" "$VPN_ROUTE_REASON" >&2
    exit 1
  fi
fi
