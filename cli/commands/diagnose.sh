#!/bin/bash
# cli/commands/diagnose.sh — 2-diagnose (PLAN.md §6).
#
# Read-only health report: product/system metadata, helper and vendor presence, bridge state,
# kernel pin, quarantine xattrs, a tunnel-default-route boolean, and NFS mount count. No privileged
# op ever runs here (diagnose never mounts/unmounts/touches pf/route).
set -u

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." &>/dev/null && pwd)"
VERSION_LIB="$SCRIPT_DIR/../lib/version.sh"
if [[ -r "$VERSION_LIB" ]]; then
  # Runtime and installed layouts resolve this file from different roots.
  # shellcheck disable=SC1090
  source "$VERSION_LIB"
  ntfsmac_load_product_version "$REPO_ROOT"
else
  NTFSMAC_VERSION="unknown"
  NTFSMAC_BUILD_VERSION="unknown"
  NTFSMAC_DIAGNOSTIC_SCHEMA_VERSION="3"
fi
# Same two candidates helper/HelperProtocol.swift's resolveNtfsmacPrefix() checks (bash and
# Swift can't share source — kept in sync deliberately, same pattern as list-drives.sh's own
# comment about its Swift-side counterpart). NTFSMAC_PREFIX matches every other command's
# convention (install.sh, uninstall.sh).
PREFIX="${NTFSMAC_PREFIX:-/usr/local/ntfsmac}"
HOMEBREW_OPT_PREFIX="/opt/homebrew/opt/ntfsmac"

json_mode=0
for arg in "$@"; do
  [[ "$arg" == "--json" ]] && json_mode=1
done

# env_override_for <name> — explicit lookup, not indirect (${!var}) expansion: macOS's
# system /bin/bash is 3.2, where indirect expansion combined with `set -u` unreliably
# errors "unbound variable" even when a `:-` default is given. A plain case statement
# is bash-3.2-safe and set -u-safe.
env_override_for() {
  case "$1" in
    anylinuxfs) printf '%s' "${NTFSMAC_ANYLINUXFS_BIN:-}" ;;
    gvproxy) printf '%s' "${NTFSMAC_GVPROXY_BIN:-}" ;;
    vmnet-helper) printf '%s' "${NTFSMAC_VMNET_HELPER_BIN:-}" ;;
    vmproxy) printf '%s' "${NTFSMAC_VMPROXY_BIN:-}" ;;
  esac
}

resolve_bin() {
  local name="$1" override_val
  override_val="$(env_override_for "$name")"
  if [[ -n "$override_val" ]]; then
    printf '%s\n' "$override_val"
    return 0
  fi

  local on_path
  on_path="$(command -v "$name" 2>/dev/null)"
  if [[ -n "$on_path" ]]; then
    printf '%s\n' "$on_path"
    return 0
  fi

  # gvproxy/vmnet-helper/vmproxy live in $PREFIX/libexec by design (install.sh, Formula) —
  # never on PATH. Checking only `command -v` reported them "missing" on every correctly
  # installed system; check both real install layouts (fixed prefix, homebrew tap) before
  # giving up.
  local prefix sub candidate
  for prefix in "$PREFIX" "$HOMEBREW_OPT_PREFIX"; do
    for sub in bin libexec; do
      candidate="$prefix/$sub/$name"
      if [[ -x "$candidate" ]]; then
        printf '%s\n' "$candidate"
        return 0
      fi
    done
  done
  return 1
}

# check_vendor_binaries — sets MISSING_BINS / QUARANTINED_BINS globals (plain scalars,
# not an associative array: macOS's system bash 3.2 has no `declare -A`).
check_vendor_binaries() {
  MISSING_BINS=0
  QUARANTINED_BINS=0
  MISSING_COMPONENTS=""
  QUARANTINED_COMPONENTS=""
  local name bin
  for name in anylinuxfs gvproxy vmnet-helper vmproxy; do
    bin="$(resolve_bin "$name")"
    if [[ -z "$bin" || ! -x "$bin" ]]; then
      MISSING_BINS=$((MISSING_BINS + 1))
      MISSING_COMPONENTS="${MISSING_COMPONENTS}${MISSING_COMPONENTS:+ }$name"
      continue
    fi
    if xattr -p com.apple.quarantine "$bin" >/dev/null 2>&1; then
      QUARANTINED_BINS=$((QUARANTINED_BINS + 1))
      QUARANTINED_COMPONENTS="${QUARANTINED_COMPONENTS}${QUARANTINED_COMPONENTS:+ }$name"
    fi
  done
}

check_kernel_pin() {
  local lock_sh="$REPO_ROOT/build/lib/lock.sh"
  if [[ ! -x "$lock_sh" ]]; then
    lock_sh="$PREFIX/libexec/ntfsmac/lib/lock.sh"
  fi

  local kernel_dir="${NTFSMAC_VENDOR_KERNEL_DIR:-$REPO_ROOT/vendor/kernel}"
  if [[ ! -d "$kernel_dir" ]]; then
    kernel_dir="$PREFIX/lib"
  fi

  if [[ ! -x "$lock_sh" ]]; then
    echo "unknown"
    return
  fi

  # Runtime and installed layouts resolve this file from different roots.
  # shellcheck disable=SC1090
  source "$lock_sh"
  local expected actual
  expected="$(lock_get LIBKRUNFW_MODULES_SHA256 2>/dev/null)" || { echo "unknown"; return; }

  local squashfs_file="$kernel_dir/modules.squashfs"
  if [[ ! -f "$squashfs_file" && -f "$PREFIX/lib/modules.squashfs" ]]; then
    squashfs_file="$PREFIX/lib/modules.squashfs"
  fi

  [[ -f "$squashfs_file" ]] || { echo "missing"; return; }
  actual="$(shasum -a 256 "$squashfs_file" | awk '{print $1}')"
  [[ "$actual" == "$expected" ]] && echo "match" || echo "mismatch"
}

# Loads the same sources.lock-derived runtime contract used by the build and mount path, then
# reports only fixed tokens plus the approved tag/digest. No home path or cache content is emitted.
check_alpine_runtime() {
  local runtime_lib="$SCRIPT_DIR/../lib/runtime-alpine.sh"
  local lock_lib
  if [[ -r "$SCRIPT_DIR/../lib/lock.sh" ]]; then
    lock_lib="$SCRIPT_DIR/../lib/lock.sh"
  else
    lock_lib="$REPO_ROOT/build/lib/lock.sh"
  fi

  ALPINE_RUNTIME_TAG="unknown"
  ALPINE_RUNTIME_DIGEST="unknown"
  ALPINE_RUNTIME_STATE="unknown"
  if [[ ! -r "$lock_lib" || ! -r "$runtime_lib" ]]; then
    return 1
  fi

  # Installed and source-tree layouts resolve the same libraries from different roots.
  # shellcheck disable=SC1090
  source "$lock_lib"
  # shellcheck disable=SC1090
  source "$runtime_lib"
  runtime_alpine_load || return 1

  local runtime_home
  runtime_home="${NTFSMAC_RUNTIME_HOME_OVERRIDE-${HOME:-}}"
  if [[ -z "$runtime_home" ]]; then
    runtime_home="$(cd ~ 2>/dev/null && pwd)"
  fi
  [[ -n "$runtime_home" ]] || return 1

  ALPINE_RUNTIME_STATE="$(runtime_alpine_cache_state "$runtime_home")" || {
    ALPINE_RUNTIME_STATE="unknown"
    return 1
  }
  return 0
}

check_bridge_up() {
  if pgrep 'vmnet-helper' >/dev/null 2>&1 || \
     pgrep 'gvproxy' >/dev/null 2>&1 || \
     pgrep 'anylinuxfs' >/dev/null 2>&1 || \
     ifconfig | grep -E "inet 172\.(1[6-9]|2[0-9]|3[0-1])\." >/dev/null 2>&1; then
    echo "up"
  else
    echo "down"
  fi
}

current_mounts() {
  mount -t nfs 2>/dev/null | awk '{print $1, "on", $3}'
}

check_architecture() {
  printf '%s\n' "${NTFSMAC_ARCHITECTURE_OVERRIDE-$(uname -m 2>/dev/null)}"
}

check_helper_installed() {
  local helper_path
  helper_path="${NTFSMAC_HELPER_PATH_OVERRIDE-/Library/PrivilegedHelperTools/com.khr898.ntfsmac.helper}"
  # The SMJobBless artifact is normally root:wheel 0544. An unprivileged caller therefore cannot
  # use `-x` to infer whether launchd/root can execute it; presence as a regular file is the honest
  # installation signal available to this read-only command.
  [[ -n "$helper_path" && -f "$helper_path" ]]
}

# Reports only whether the default route is carried by a tunnel. It deliberately omits the
# interface name, VPN provider, addresses, routes, and DNS details from both human and JSON output.
check_vpn_default_route() {
  local interface
  interface="${NTFSMAC_DEFAULT_INTERFACE_OVERRIDE-$(route -n get default 2>/dev/null | awk '/interface:/{print $2; exit}')}"
  case "$interface" in
    utun* | ppp* | tun*) return 0 ;;
    *) return 1 ;;
  esac
}

count_mounts() {
  local mounts="$1"
  if [[ -n "${NTFSMAC_NFS_MOUNT_COUNT_OVERRIDE-}" ]]; then
    printf '%s\n' "$NTFSMAC_NFS_MOUNT_COUNT_OVERRIDE"
    return
  fi
  printf '%s\n' "$mounts" | awk 'NF { count++ } END { print count + 0 }'
}

# Component names are fixed internal tokens (never paths or user-provided values), so this small
# Bash-3.2-compatible formatter can emit them without adding a jq/Python runtime dependency.
component_json_array() {
  local components="$1" component first=1
  printf '['
  for component in $components; do
    [[ "$first" -eq 1 ]] || printf ','
    printf '"%s"' "$component"
    first=0
  done
  printf ']'
}

# check_macos_version — reports the macOS product version. Two reasons diagnose grew this:
# (1) triage reports (see README "Troubleshooting" / the issue tracker) kept omitting the OS
# version, so the first ask on every "installed but not working" report was "which macOS?";
# (2) ntfsmac requires macOS 13.0+, so an older host is a real cause of that symptom, worth
# flagging directly. Overridable for tests via NTFSMAC_MACOS_VERSION_OVERRIDE — note the `-`
# (not `:-`) default: an explicitly-set empty value simulates sw_vers returning nothing
# (reported as "unknown"), while leaving it unset runs sw_vers normally. bash-3.2 + set -u
# safe (plain default expansion, no indirect ${!var}).
check_macos_version() {
  local ver
  ver="${NTFSMAC_MACOS_VERSION_OVERRIDE-$(sw_vers -productVersion 2>/dev/null)}"
  if [[ -n "$ver" ]]; then
    printf '%s\n' "$ver"
  else
    printf 'unknown\n'
  fi
}

main() {
  local kernel_pin bridge mounts mount_count architecture healthy=1
  local macos_version macos_major macos_supported=1
  local helper_installed=0 vpn_default_route=0
  local helper_json vpn_json missing_json quarantined_json healthy_json
  MISSING_BINS=0
  QUARANTINED_BINS=0
  MISSING_COMPONENTS=""
  QUARANTINED_COMPONENTS=""

  macos_version="$(check_macos_version)"
  architecture="$(check_architecture)"
  check_vendor_binaries
  kernel_pin="$(check_kernel_pin)"
  bridge="$(check_bridge_up)"
  mounts="$(current_mounts)"
  mount_count="$(count_mounts "$mounts")"
  check_helper_installed && helper_installed=1
  check_vpn_default_route && vpn_default_route=1
  check_alpine_runtime || true

  # ntfsmac requires macOS 13.0+ on Apple Silicon. Only a real, parseable major version
  # below 13 flips health; an unknown/undetected version is reported but left non-fatal.
  # Portable "is it all digits" test (case glob) instead of a regex — bash-3.2 safe.
  macos_major="${macos_version%%.*}"
  case "$macos_major" in
    ''|*[!0-9]*) macos_major="" ;;
  esac
  if [[ -n "$macos_major" && "$macos_major" -lt 13 ]]; then
    healthy=0
    macos_supported=0
  fi

  [[ "$MISSING_BINS" -gt 0 ]] && healthy=0
  [[ "$QUARANTINED_BINS" -gt 0 ]] && healthy=0
  [[ "$kernel_pin" == "mismatch" || "$kernel_pin" == "missing" ]] && healthy=0
  [[ "$architecture" != "arm64" ]] && healthy=0
  case "$ALPINE_RUNTIME_STATE" in
    initialized|not_initialized|migration_available) ;;
    *) healthy=0 ;;
  esac

  if [[ $json_mode -eq 1 ]]; then
    [[ "$healthy" -eq 1 ]] && healthy_json=true || healthy_json=false
    [[ "$helper_installed" -eq 1 ]] && helper_json=true || helper_json=false
    [[ "$vpn_default_route" -eq 1 ]] && vpn_json=true || vpn_json=false
    missing_json="$(component_json_array "$MISSING_COMPONENTS")"
    quarantined_json="$(component_json_array "$QUARANTINED_COMPONENTS")"
    printf '{"diagnostic_schema":%s,"healthy":%s,"ntfsmac_version":"%s","build_version":"%s","macos_version":"%s","architecture":"%s","helper_installed":%s,"missing_binaries":%s,"missing_components":%s,"quarantined_binaries":%s,"quarantined_components":%s,"kernel_pin":"%s","alpine_runtime_tag":"%s","alpine_runtime_digest":"%s","alpine_runtime_state":"%s","bridge":"%s","vpn_default_route":%s,"nfs_mount_count":%s}\n' \
      "$NTFSMAC_DIAGNOSTIC_SCHEMA_VERSION" "$healthy_json" "$NTFSMAC_VERSION" \
      "$NTFSMAC_BUILD_VERSION" "$macos_version" "$architecture" "$helper_json" \
      "$MISSING_BINS" "$missing_json" "$QUARANTINED_BINS" "$quarantined_json" \
      "$kernel_pin" "$ALPINE_RUNTIME_TAG" "$ALPINE_RUNTIME_DIGEST" \
      "$ALPINE_RUNTIME_STATE" "$bridge" "$vpn_json" "$mount_count"
  else
    echo "diagnose: ntfsmac version: $NTFSMAC_VERSION ($NTFSMAC_BUILD_VERSION)"
    echo "diagnose: macOS version: $macos_version"
    [[ "$macos_supported" -eq 0 ]] && echo "diagnose:   unsupported — ntfsmac requires macOS 13.0+"
    echo "diagnose: architecture: $architecture"
    [[ "$architecture" != "arm64" ]] && echo "diagnose:   unsupported — ntfsmac requires Apple Silicon"
    echo "diagnose: privileged helper: $([[ "$helper_installed" -eq 1 ]] && echo installed || echo not installed)"
    echo "diagnose: vendor binaries missing: $MISSING_BINS"
    [[ -n "$MISSING_COMPONENTS" ]] && echo "diagnose:   missing components: $MISSING_COMPONENTS"
    echo "diagnose: quarantined binaries: $QUARANTINED_BINS"
    [[ -n "$QUARANTINED_COMPONENTS" ]] && echo "diagnose:   quarantined components: $QUARANTINED_COMPONENTS"
    echo "diagnose: kernel pin: $kernel_pin"
    echo "diagnose: Alpine runtime: $ALPINE_RUNTIME_TAG ($ALPINE_RUNTIME_DIGEST)"
    echo "diagnose: Alpine runtime state: $ALPINE_RUNTIME_STATE"
    echo "diagnose: vmnet bridge: $bridge"
    echo "diagnose: VPN default route: $([[ "$vpn_default_route" -eq 1 ]] && echo detected || echo not detected)"
    echo "diagnose: current NFS mount count: $mount_count"
    echo "diagnose: overall: $([[ $healthy -eq 1 ]] && echo healthy || echo degraded)"
  fi

  [[ $healthy -eq 1 ]]
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
