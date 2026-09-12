#!/bin/bash
# Read the exact partition's superblock without starting a VM or mounting it.
set -u
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
source "$SCRIPT_DIR/../lib/validate-device.sh"
source "$SCRIPT_DIR/../lib/resolve-vendor-bin.sh"
source "$SCRIPT_DIR/../lib/run-with-progress.sh"

if [[ $# -ne 1 || "${1:-}" == --help || "${1:-}" == -h ]]; then
  echo 'usage: ntfsmac filesystem <diskNsM> (read-only JSON metadata)' >&2
  [[ "${1:-}" == --help || "${1:-}" == -h ]] && exit 0
  exit 1
fi
validate_device "$1" || exit 1
if [[ $EUID -ne 0 && "${NTFSMAC_SKIP_ROOT_CHECK:-}" != 1 ]]; then
  exec sudo "$0" "$@"
fi
ANYLINUXFS_BIN="${NTFSMAC_ANYLINUXFS_BIN:-$(resolve_vendor_bin anylinuxfs || true)}"
[[ -n "$ANYLINUXFS_BIN" ]] || { echo 'filesystem: runtime is missing; reinstall ntfsmac' >&2; exit 1; }
# Older anylinuxfs treats unknown commands as an implicit mount. Never dispatch this
# new operation unless the native CLI advertises it explicitly.
probe_help="$(run_with_progress 2 1 'filesystem: checking runtime' - "$ANYLINUXFS_BIN" --help 2>&1)" || {
  echo 'filesystem: could not check runtime support' >&2
  exit 1
}
[[ "$probe_help" == *"probe-filesystem"* ]] || { echo 'filesystem: runtime is outdated; reinstall ntfsmac' >&2; exit 1; }
run_with_progress 10 5 'filesystem: reading metadata' - "$ANYLINUXFS_BIN" probe-filesystem "$1"
