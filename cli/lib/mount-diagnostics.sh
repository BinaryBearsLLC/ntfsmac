#!/bin/bash
# shellcheck disable=SC2034
# Privacy-safe last mount-attempt driver/result record. The file never contains a device, path,
# label, backend output, or network identity.

mount_diagnostics_reset() {
  MOUNT_DIAGNOSTICS_DRIVER="unknown"
  MOUNT_DIAGNOSTICS_FAILURE="unknown"
}

mount_diagnostics_valid_driver() {
  case "${1:-}" in ntfs-3g|ntfs3|ext|none|unknown) return 0 ;; *) return 1 ;; esac
}

mount_diagnostics_valid_failure() {
  case "${1:-}" in
    none|in_progress|invalid_request|runtime_unavailable|backend_failed|backend_timeout|mount_not_observed|unknown) return 0 ;;
    *) return 1 ;;
  esac
}

mount_diagnostics_file() {
  printf '%s\n' "${NTFSMAC_MOUNT_DIAGNOSTICS_FILE:-/var/run/ntfsmac/mount-diagnostics}"
}

mount_diagnostics_publish() {
  local driver="$1" failure="$2" status_file parent owner parent_mode status_tmp
  mount_diagnostics_valid_driver "$driver" || return 1
  mount_diagnostics_valid_failure "$failure" || return 1
  status_file="$(mount_diagnostics_file)"
  parent="$(dirname "$status_file")"
  [[ ! -L "$parent" ]] || return 1
  mkdir -p "$parent" || return 1
  [[ -d "$parent" && ! -L "$parent" ]] || return 1
  owner="$(stat -f '%u' "$parent" 2>/dev/null)" || return 1
  [[ "$owner" == "$EUID" ]] || return 1
  parent_mode="$(stat -f '%Lp' "$parent" 2>/dev/null)" || return 1
  [[ "$parent_mode" =~ ^[0-7]{3,4}$ ]] || return 1
  (( (8#$parent_mode & 8#22) == 0 )) || return 1
  if [[ -e "$status_file" || -L "$status_file" ]]; then
    [[ -f "$status_file" && ! -L "$status_file" ]] || return 1
  fi
  status_tmp="$(mktemp "${status_file}.XXXXXX")" || return 1
  chmod 644 "$status_tmp" 2>/dev/null || { rm -f "$status_tmp"; return 1; }
  printf 'schema=1\nselected_driver=%s\nfailure_category=%s\n' "$driver" "$failure" > "$status_tmp"
  mv -f "$status_tmp" "$status_file" || { rm -f "$status_tmp"; return 1; }
}

mount_diagnostics_load() {
  mount_diagnostics_reset
  local status_file parent expected_owner="0" owner mode parent_mode line key value schema="" driver="" failure="" seen=""
  status_file="$(mount_diagnostics_file)"
  parent="$(dirname "$status_file")"
  [[ -n "${NTFSMAC_MOUNT_DIAGNOSTICS_FILE+x}" ]] && expected_owner="$(id -u)"
  [[ -d "$parent" && ! -L "$parent" ]] || return 1
  owner="$(stat -f '%u' "$parent" 2>/dev/null)" || return 1
  [[ "$owner" == "$expected_owner" ]] || return 1
  parent_mode="$(stat -f '%Lp' "$parent" 2>/dev/null)" || return 1
  [[ "$parent_mode" =~ ^[0-7]{3,4}$ ]] || return 1
  (( (8#$parent_mode & 8#22) == 0 )) || return 1
  [[ -f "$status_file" && ! -L "$status_file" ]] || return 1
  [[ "$(wc -c < "$status_file" 2>/dev/null)" -le 1024 ]] || return 1
  owner="$(stat -f '%u' "$status_file" 2>/dev/null)" || return 1
  [[ "$owner" == "$expected_owner" ]] || return 1
  mode="$(stat -f '%Lp' "$status_file" 2>/dev/null)" || return 1
  [[ "$mode" =~ ^[0-7]{3,4}$ ]] || return 1
  (( (8#$mode & 8#22) == 0 )) || return 1
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" == *=* ]] || return 1
    key="${line%%=*}"; value="${line#*=}"
    [[ " $seen " != *" $key "* ]] || return 1
    seen="$seen $key"
    case "$key" in
      schema) schema="$value" ;;
      selected_driver) driver="$value" ;;
      failure_category) failure="$value" ;;
      *) return 1 ;;
    esac
  done < "$status_file"
  [[ "$schema" == "1" ]] || return 1
  mount_diagnostics_valid_driver "$driver" || return 1
  mount_diagnostics_valid_failure "$failure" || return 1
  MOUNT_DIAGNOSTICS_DRIVER="$driver"
  MOUNT_DIAGNOSTICS_FAILURE="$failure"
}
