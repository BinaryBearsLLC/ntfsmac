#!/bin/bash
# cli/lib/pf-anchor.sh — 1-pf-rules (PLAN.md §6, L2, L8; Phase 1 defense-in-depth).
#
# Renders one per-session anchor for a measured /30 + bridge. The installed anchor lives below
# `com.apple/ntfsmac-diskNsM`, a direct child reached by macOS's default `anchor "com.apple/*"`
# rule (PF wildcard anchors do not recurse into grandchildren). Rules
# use `quick` and are interface/subnet-scoped so they cannot turn a nested anchor into a global
# host firewall.
set -u

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
TEMPLATE="${NTFSMAC_PF_TEMPLATE:-$SCRIPT_DIR/../pf/ntfsmac.anchor.tmpl}"

valid_vmnet_subnet() {
  local subnet="${1:-}" address a b c d prefix
  address="${subnet%/*}"
  prefix="${subnet##*/}"
  [[ "$prefix" == "30" && "$address" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] \
    || return 1
  IFS=. read -r a b c d <<< "$address"
  a=$((10#$a)); b=$((10#$b)); c=$((10#$c)); d=$((10#$d))
  [[ "$a" -eq 172 && "$b" -ge 16 && "$b" -le 31 && "$c" -le 255 && "$d" -le 255 \
    && $((d % 4)) -eq 0 ]]
}

# render_pf_anchor <subnet-cidr> <bridge-interface> [session-id]
render_pf_anchor() {
  local subnet="${1:-}" interface="${2:-}" session="${3:-legacy}"
  if [[ -z "$subnet" || -z "$interface" ]]; then
    echo "pf-anchor: subnet CIDR and bridge interface are required" >&2
    return 1
  fi
  # Security review finding (2026-07-13, LOW, defense-in-depth): the `sed` substitution below
  # only fails safe on delimiter/newline abuse by accident of BSD sed's own parser — a valid but
  # over-wide CIDR (e.g. 0.0.0.0/0) previously sailed through untouched. The live transaction
  # now derives this subnet from a validated vmnet endpoint, but this renderer keeps its own
  # independent private-/30 gate so direct invocation cannot widen policy scope.
  if ! valid_vmnet_subnet "$subnet"; then
    echo "pf-anchor: subnet CIDR must be a canonical anylinuxfs vmnet /30 (got \"$subnet\")" >&2
    return 1
  fi
  if [[ ! "$interface" =~ ^bridge[0-9]+$ ]]; then
    echo "pf-anchor: interface must match bridgeN (got \"$interface\")" >&2
    return 1
  fi
  if [[ ! "$session" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo "pf-anchor: invalid session identifier" >&2
    return 1
  fi
  if [[ ! -f "$TEMPLATE" ]]; then
    echo "pf-anchor: template not found: $TEMPLATE" >&2
    return 1
  fi
  sed -e "s|{{SUBNET}}|$subnet|g" \
    -e "s|{{INTERFACE}}|$interface|g" \
    -e "s|{{SESSION}}|$session|g" "$TEMPLATE"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  render_pf_anchor "$@"
fi
