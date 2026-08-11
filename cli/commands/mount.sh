#!/bin/bash
# cli/commands/mount.sh — 2-mount + 2-fs-driver-flag (PLAN.md §6, L1, L3, L6).
set -u

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
# shellcheck source=../lib/validate-device.sh
source "$SCRIPT_DIR/../lib/validate-device.sh"
# shellcheck source=../lib/nfs-mount.sh
source "$SCRIPT_DIR/../lib/nfs-mount.sh"
# shellcheck source=../lib/list-drives.sh
source "$SCRIPT_DIR/../lib/list-drives.sh"
# shellcheck source=../lib/interactive-select.sh
source "$SCRIPT_DIR/../lib/interactive-select.sh"
# shellcheck source=../lib/security-transaction.sh
source "$SCRIPT_DIR/../lib/security-transaction.sh"

usage() {
  echo "usage: mount.sh [--fs-driver ntfs-3g|ntfs3] [--read-only] [--ignore-permissions] <device> [mount_point]" >&2
}

cmd_mount() {
  # Real, upstream-documented requirement (vendor/src/anylinuxfs/docs/important-notes.md
  # "Permissions"): anylinuxfs needs raw /dev/disk* access, which macOS refuses without root
  # (it drops back to the invoking user once the disk is open — this isn't a permanent
  # privilege escalation). Self-elevates via sudo (prompts for the password interactively)
  # instead of just erroring and making the user retype the whole command — same one-time
  # auth UX as install.sh's own sudo path for the GUI helper removal. `exec` replaces this
  # process outright, so mount.sh's own exit status becomes whatever the re-run (as root)
  # produces; sudo's own prompt/failure handling covers a wrong password or a Ctrl-C.
  # Transparent to the GUI: its privileged helper already runs as root, so this never fires.
  if [[ $EUID -ne 0 && "${NTFSMAC_SKIP_ROOT_CHECK:-}" != "1" ]]; then
    exec sudo "$0" "$@"
  fi

  # Recover only stale protection records before allocating another session. An unavailable
  # runtime status source is fail-closed: reconciliation preserves all existing anchors/routes.
  security_reconcile >/dev/null || true

  local fs_driver="" device="" mount_point="" read_only="" ignore_perms=""
  local -a positional=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --fs-driver)
        [[ $# -ge 2 ]] || { echo "mount: --fs-driver requires a value" >&2; return 1; }
        fs_driver="$2"
        shift 2
        ;;
      --fs-driver=*)
        fs_driver="${1#*=}"
        shift
        ;;
      --read-only)
        read_only="1"
        shift
        ;;
      # ext drives need all_squash on the NFS export so the macOS user can write past ext's
      # Unix ownership (see nfs-mount.sh). The GUI helper passes this for ext as its signal
      # that the drive is ext-family — and to skip the fstype probe below. A CLI user can also
      # set it explicitly for an ext drive the probe missed (e.g. a wedged `anylinuxfs list`).
      --ignore-permissions)
        ignore_perms="1"
        shift
        ;;
      --)
        shift
        positional+=("$@")
        break
        ;;
      -*)
        echo "mount: unknown option: $1" >&2
        usage
        return 1
        ;;
      *)
        positional+=("$1")
        shift
        ;;
    esac
  done

  device="${positional[0]:-}"
  mount_point="${positional[1]:-}"

  # No device given: list compatible drives instead of just erroring on missing args.
  local chosen_fstype=""
  if [[ -z "$device" ]]; then
    local -a idents=() fstypes=() menu_lines=()
    local ident label size fstype rest
    local drives_tmp
    drives_tmp="$(mktemp)"
    # Real exit status, not process substitution: list_mountable_drives() returns 1 (with its
    # own clear "no response" message already printed) on a backend timeout — that must short-
    # circuit here, not fall through to the generic "no compatible drives found" below, which
    # would misreport a wedged backend as an empty drive list.
    if ! list_mountable_drives > "$drives_tmp"; then
      rm -f "$drives_tmp"
      return 1
    fi
    # Split on tab manually, NOT `IFS=$'\t' read`: tab is a whitespace IFS char, so `read`
    # collapses an empty label field (unlabeled ext drives emit `ident\t\t<size>\t<fstype>`),
    # shifting size→label, fstype→size, fstype="". That made the picker lose fstype, so ext
    # never got --ignore-permissions (no noowners → read-only). Swift's split(separator:) does
    # NOT collapse empty fields — that's why the GUI worked and the CLI didn't. Parameter
    # expansion preserves every field, empty or not. Same fix in list-drives.sh:fs_type_for_device.
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      rest="${line#*$'\t'}"; ident="${line%%$'\t'*}"
      label="${rest%%$'\t'*}"; rest="${rest#*$'\t'}"
      size="${rest%%$'\t'*}"; rest="${rest#*$'\t'}"
      fstype="${rest%%$'\t'*}"
      [[ -n "$ident" ]] || continue
      idents+=("$ident")
      fstypes+=("$fstype")
      menu_lines+=("/dev/$ident  $label  $size  $fstype")
    done < "$drives_tmp"
    rm -f "$drives_tmp"

    if [[ ${#idents[@]} -eq 0 ]]; then
      echo "mount: no compatible drives found (plug one in, or pass a device explicitly)" >&2
      return 1
    fi

    echo "mount: compatible drives:" >&2
    local i
    for i in "${!menu_lines[@]}"; do
      printf '  %d) %s\n' "$((i + 1))" "${menu_lines[$i]}" >&2
    done

    local choice
    choice="$(prompt_choice "${#idents[@]}")" || { echo "mount: cancelled" >&2; return 1; }
    local idx=$((choice - 1))
    device="${idents[$idx]}"
    chosen_fstype="${fstypes[$idx]}"
  fi

  if [[ -n "$fs_driver" && "$fs_driver" != "ntfs-3g" && "$fs_driver" != "ntfs3" ]]; then
    echo "mount: invalid --fs-driver '$fs_driver' (must be ntfs-3g or ntfs3)" >&2
    return 1
  fi
  # Remember whether --fs-driver was explicitly given before ntfs-3g is cleared to "" below —
  # the auto-detect uses this to skip the fstype probe when the caller already named an NTFS
  # driver (the GUI helper passes --fs-driver for ntfs; only the direct/picker CLI paths with
  # no --fs-driver auto-probe for ext).
  local explicit_driver="$fs_driver"
  # ntfs-3g is the implicit default (L1) — only pass -t to opt into ntfs3.
  [[ "$fs_driver" == "ntfs-3g" ]] && fs_driver=""

  if ! validate_device "$device"; then
    return 1
  fi

  # ext needs --ignore-permissions (all_squash) so the macOS user can write past ext's Unix
  # ownership (see nfs-mount.sh). Only auto-set it when the caller didn't already pass
  # --ignore-permissions AND didn't explicitly name an NTFS driver — the picker already has
  # the fstype in hand (no probe), the direct path probes fs_type_for_device (one `anylinuxfs
  # list`). NTFS is left untouched: "do not change the NTFS part".
  if [[ -z "$ignore_perms" && -z "$explicit_driver" ]]; then
    local fstype="$chosen_fstype"
    if [[ -z "$fstype" ]]; then
      fstype="$(fs_type_for_device "$device")"
    fi
    case "$fstype" in
      ext|ext2|ext3|ext4) ignore_perms="1" ;;
    esac
  fi

  if run_anylinuxfs_mount "$device" "$fs_driver" "$mount_point" "$read_only" "$ignore_perms"; then
    # anylinuxfs currently owns private-link creation and the host NFS mount as one operation, so
    # Option A applies/measures protection immediately after the kernel mount but before this
    # wrapper publishes "mounted". A failed proof remains visible and never becomes a green state.
    security_apply_for_mount "$device" || \
      echo "security_overall=unknown reason=SECURITY_TRANSACTION_FAILED" >&2
    echo "mount: $device mounted"
    return 0
  fi
  echo "mount: failed to mount $device" >&2
  return 1
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  cmd_mount "$@"
fi
