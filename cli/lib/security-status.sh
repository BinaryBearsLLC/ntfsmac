#!/bin/bash
# shellcheck disable=SC2034
# Read the privacy-safe aggregate security status published by the privileged transaction. The
# root-only per-session files intentionally remain unreadable to the CLI and GUI.

security_summary_reset() {
  SECURITY_ACTIVE_SESSIONS="unknown"
  SECURITY_PRIVATE_LINK="unknown"
  SECURITY_PRIVATE_REASON="STATUS_UNAVAILABLE"
  SECURITY_VPN_ROUTE="unknown"
  SECURITY_VPN_ROUTE_REASON="STATUS_UNAVAILABLE"
  SECURITY_PF_POLICY="unknown"
  SECURITY_PF_REASON="STATUS_UNAVAILABLE"
  SECURITY_OVERALL="unknown"
  SECURITY_OVERALL_REASON="STATUS_UNAVAILABLE"
}

security_summary_valid_state() {
  case "${1:-}" in
    enforced|notEnforced|notRequired|unknown) return 0 ;;
    *) return 1 ;;
  esac
}

security_summary_valid_reason() {
  [[ -n "${1:-}" && "$1" != *[!A-Z0-9_]* ]]
}

security_summary_load() {
  security_summary_reset
  local default_file="/var/run/ntfsmac/security-status"
  local status_file parent
  status_file="${NTFSMAC_SECURITY_STATUS_FILE:-$default_file}"
  parent="$(dirname "$status_file")"
  local expected_owner="0" owner mode parent_mode line key value
  local schema="" active="" private="" private_reason="" route="" route_reason=""
  local pf="" pf_reason="" overall="" overall_reason="" seen=""

  [[ -n "${NTFSMAC_SECURITY_STATUS_FILE+x}" ]] && expected_owner="$(id -u)"
  [[ -d "$parent" && ! -L "$parent" ]] || return 1
  owner="$(stat -f '%u' "$parent" 2>/dev/null)" || return 1
  [[ "$owner" == "$expected_owner" ]] || return 1
  parent_mode="$(stat -f '%Lp' "$parent" 2>/dev/null)" || return 1
  [[ "$parent_mode" =~ ^[0-7]{3,4}$ ]] || return 1
  (( (8#$parent_mode & 8#22) == 0 )) || return 1
  [[ -f "$status_file" && ! -L "$status_file" ]] || return 1
  [[ "$(wc -c < "$status_file" 2>/dev/null)" -le 4096 ]] || return 1
  owner="$(stat -f '%u' "$status_file" 2>/dev/null)" || return 1
  [[ "$owner" == "$expected_owner" ]] || return 1
  mode="$(stat -f '%Lp' "$status_file" 2>/dev/null)" || return 1
  [[ "$mode" =~ ^[0-7]{3,4}$ ]] || return 1
  (( (8#$mode & 8#22) == 0 )) || return 1

  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" == *=* ]] || return 1
    key="${line%%=*}"
    value="${line#*=}"
    [[ " $seen " != *" $key "* ]] || return 1
    seen="$seen $key"
    case "$key" in
      schema) schema="$value" ;;
      active_sessions) active="$value" ;;
      private_link) private="$value" ;;
      private_reason) private_reason="$value" ;;
      vpn_route) route="$value" ;;
      vpn_route_reason) route_reason="$value" ;;
      pf_policy) pf="$value" ;;
      pf_reason) pf_reason="$value" ;;
      overall) overall="$value" ;;
      overall_reason) overall_reason="$value" ;;
      *) return 1 ;;
    esac
  done < "$status_file"

  [[ "$schema" == "1" ]] || return 1
  [[ "$active" == "unknown" || ( -n "$active" && "$active" != *[!0-9]* ) ]] || return 1
  security_summary_valid_state "$private" || return 1
  security_summary_valid_state "$route" || return 1
  security_summary_valid_state "$pf" || return 1
  security_summary_valid_state "$overall" || return 1
  security_summary_valid_reason "$private_reason" || return 1
  security_summary_valid_reason "$route_reason" || return 1
  security_summary_valid_reason "$pf_reason" || return 1
  security_summary_valid_reason "$overall_reason" || return 1

  SECURITY_ACTIVE_SESSIONS="$active"
  SECURITY_PRIVATE_LINK="$private"
  SECURITY_PRIVATE_REASON="$private_reason"
  SECURITY_VPN_ROUTE="$route"
  SECURITY_VPN_ROUTE_REASON="$route_reason"
  SECURITY_PF_POLICY="$pf"
  SECURITY_PF_REASON="$pf_reason"
  SECURITY_OVERALL="$overall"
  SECURITY_OVERALL_REASON="$overall_reason"
}
