#!/bin/bash
# Open the BinaryBears menu-bar popover through its registered URL event. This works whether the
# app is already running or must be launched, and needs no Accessibility permission or simulated
# mouse click.
set -u

usage() {
  cat <<'HELP'
usage: opengui.sh

Open the ntfsmac menu-bar popover. The GUI application must be installed and registered with
macOS Launch Services.
HELP
}

main() {
  case "${1:-}" in
    --help|-h)
      usage
      return 0
      ;;
    "") ;;
    *)
      echo "opengui: unexpected argument '$1'" >&2
      usage >&2
      return 2
      ;;
  esac
  [[ $# -le 1 ]] || {
    echo "opengui: no arguments are accepted" >&2
    usage >&2
    return 2
  }

  local open_bin="${NTFSMAC_OPEN_BIN:-/usr/bin/open}"
  local notify_bin="${NTFSMAC_NOTIFY_BIN:-/usr/bin/notifyutil}"
  local bundle_id="${NTFSMAC_GUI_BUNDLE_ID:-com.binarybears.ntfsmac}"
  local app_path="${NTFSMAC_GUI_APP_PATH:-}"
  local request_url="binarybears-ntfsmac://opengui"
  local notification_name="com.binarybears.ntfsmac.open-gui"
  local -a request_args

  post_reveal_notification() {
    [[ -x "$notify_bin" ]] || return 0
    "$notify_bin" -q -p "$notification_name" >/dev/null 2>&1 || true
  }

  [[ -x "$open_bin" ]] || {
    echo "opengui: macOS open tool is unavailable" >&2
    return 1
  }

  if [[ -n "$app_path" ]]; then
    [[ -d "$app_path" && "$app_path" == *.app ]] || {
      echo "opengui: NTFSMAC_GUI_APP_PATH must name an existing .app bundle" >&2
      return 1
    }
    request_args=(-a "$app_path" "$request_url")
  else
    request_args=(-b "$bundle_id" "$request_url")
  fi

  "$open_bin" "${request_args[@]}" || {
    if [[ -n "$app_path" ]]; then
      echo "opengui: unable to launch '$app_path'" >&2
    else
      echo "opengui: ntfsmac.app is not installed or registered" >&2
    fi
    return 1
  }
  post_reveal_notification

  # Launch Services can return after creating a cold process but before its reveal listener is
  # ready. Re-sending the idempotent launch URL plus the local Darwin notification across the
  # first second closes that race without Accessibility permission, synthetic clicks, or an
  # always-running control socket. A warm app simply receives the same harmless request again.
  /bin/sleep 0.4
  "$open_bin" "${request_args[@]}" || {
    echo "opengui: app launched, but the popover request could not be delivered" >&2
    return 1
  }
  post_reveal_notification
  /bin/sleep 0.5
  "$open_bin" "${request_args[@]}" || {
    echo "opengui: app launched, but the final popover request could not be delivered" >&2
    return 1
  }
  post_reveal_notification

  echo "opengui: popover requested"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
