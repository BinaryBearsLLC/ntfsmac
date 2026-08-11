#!/bin/bash
# Compatibility entrypoint for per-session security cleanup.
#
#   pf-teardown.sh diskNsM  — remove exactly one mount's anchor/token/owned route
#   pf-teardown.sh          — reconcile stale sessions only; never touches active mounts
#   pf-teardown.sh --all    — remove every recorded session (uninstall/no-mount contexts only)
set -u

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
# shellcheck source=security-transaction.sh
# shellcheck disable=SC1091
source "$SCRIPT_DIR/security-transaction.sh"

teardown_pf() {
  local target="${1:-}"
  case "$target" in
    --all) security_teardown_all ;;
    "") security_reconcile ;;
    disk[0-9]*s[0-9]*) security_teardown_session "$target" ;;
    *)
      echo "pf-teardown: expected diskNsM, --all, or no argument" >&2
      return 1
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  teardown_pf "$@"
fi
