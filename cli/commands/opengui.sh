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
  local bundle_id="${NTFSMAC_GUI_BUNDLE_ID:-com.khr898.ntfsmac}"
  local app_path="${NTFSMAC_GUI_APP_PATH:-}"
  local request_url="binarybears-ntfsmac://opengui"

  [[ -x "$open_bin" ]] || {
    echo "opengui: macOS open tool is unavailable" >&2
    return 1
  }

  if [[ -n "$app_path" ]]; then
    [[ -d "$app_path" && "$app_path" == *.app ]] || {
      echo "opengui: NTFSMAC_GUI_APP_PATH must name an existing .app bundle" >&2
      return 1
    }
    "$open_bin" -a "$app_path" "$request_url" || {
      echo "opengui: unable to launch '$app_path'" >&2
      return 1
    }
  else
    "$open_bin" -b "$bundle_id" "$request_url" || {
      echo "opengui: ntfsmac.app is not installed or registered" >&2
      return 1
    }
  fi

  echo "opengui: popover requested"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
